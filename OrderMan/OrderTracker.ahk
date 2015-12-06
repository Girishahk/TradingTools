/*
  Copyright (C) 2015  SpiffSpaceman

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>
*/

/*
	Opens Order book and fetches all order details
*/
readOrderBook(){	
	
	openOrderBook()	
	readColumnHeaders()											// Find required columns in orderbook	
	readOpenOrders()
	readCompletedOrders()	
}

/*
	Register Order Tracking Timer Function
*/
initializeStatusTracker(){
	global ORDERBOOK_POLL_TIME
	SetTimer, orderStatusTracker, % ORDERBOOK_POLL_TIME
	SetTimer, orderStatusTracker, off
}

/*
	Turn order book tracking on/off
*/
toggleStatusTracker( on_off ){
	
	static isTimerActive := false
	
	if( on_off == "on" ){
		if( !isTimerActive ){
			isTimerActive := true
			SetTimer, orderStatusTracker, on
		}
	}
	else if( on_off == "off"  ){
		if( isTimerActive ){
			isTimerActive := false
			SetTimer, orderStatusTracker, off
		}
	}
	return isTimerActive
}

/*
	Tracker thread that reads orders in orderbook using Timer and updates stuff on change
	Also creates pending order if Stop Entry order was triggered
*/
orderStatusTracker(){
	Critical 														// Mark Timer thread Data fetch as Critical to avoid any possible Mixup with main thread 
																	// Marking it as critical should avoid Main thread from running
	refreshLinkedOrderDetails()										// Otherwise can get problem with entryOrderNOW / stopOrderNOW in unlink()
	createSLOrderOnEntryTrigger()
	Critical , off
	
	updateStatus()
}

doOpenOrdersExist(){
	global
	
	readOpenOrders()
	return OpenOrders.size > 0 
}

getOpenOrderCount(){
	global
	return OpenOrders.size
}

getCompletedOrderCount(){
	global
	return CompletedOrders.size
}

/*
   Get Order ID of newly opened orders, searches both open and completed orders
   Assuming only 1 opened/completed since last read
   So readOpenOrders(),readCompletedOrders() should be called before creating new order and
	  getNewOrder() should be immediately called after creating new order
   
   Returns order object if found, -1 if not found
*/
getNewOrder(){											
	global OpenOrders, CompletedOrders, NEW_ORDER_WAIT_TIME
	
	openOrdersOld		:=  OpenOrders
	completedOrdersOld  :=  CompletedOrders
	
	Loop, % NEW_ORDER_WAIT_TIME {								// Wait for new order to show up in OrderBook
		readOpenOrders()
		readCompletedOrders()
		
		if( openOrdersOld.size < OpenOrders.size || completedOrdersOld.size < CompletedOrders.size )
			break
		Sleep, 1000
	}
	if( openOrdersOld.size >= OpenOrders.size  && completedOrdersOld.size >= CompletedOrders.size )
		return -1
		
	foundOrder := getNewOrder_( openOrdersOld, OpenOrders )		// Find order that doesnt exist in openOrdersOld / completedOrdersOld
	if( foundOrder ==-1 )
		foundOrder := getNewOrder_( completedOrdersOld, CompletedOrders )	

	return foundOrder
}

/*
	Link with Input Order
	Linking Stop Order is optional
*/
linkOrders( entryOrderID, stopOrderID, isStopLinked ){
	
	global entryOrderNOW, stopOrderNOW
	
	readOrderBook()
	
	order := getOrderDetails( entryOrderID )
	if( order == -1 ){
		MsgBox, 262144,, Order %entryOrderID% Not found
		return false
	}
		
	order2 := getOrderDetails( stopOrderID )
	if( order2 == -1 && isStopLinked ){		
		MsgBox, 262144,, Order %stopOrderID% Not found
		return false
	}
	
	if( isStopLinked && (order.tradingSymbol != order2.tradingSymbol)  ){
		MsgBox, 262144,, Orders have different Trading Symbols 
		return false	
	}
	
	entryOrderNOW := order
	stopOrderNOW  := order2
	return true
}

/*
	Reset All Order pointers
*/
unlinkOrders(){
	global
	
	entryOrderNOW := -1
	stopOrderNOW  := -1
	pendingStop	  := -1
}

/*
	Search input NOW order number in Order Book 
	Returns order details if found else -1
	Run readOrderBook() before calling getOrderDetails() to get latest data
*/
getOrderDetails( inNowOrderNo ){
	
	global OpenOrders, CompletedOrders
		
	order := getOrderDetails_(OpenOrders,  inNowOrderNo )
	if( order == -1 ){
		order := getOrderDetails_(CompletedOrders,  inNowOrderNo )
	}
	return order
}

/*
	Read Orderbook, refresh Entry and Stop order Details
*/
refreshLinkedOrderDetails(){	
	global
	
	readOrderBook()
	
	if( IsObject(entryOrderNOW) )
		entryOrderNOW := getOrderDetails( entryOrderNOW.nowOrderNo )
	
	if( IsObject(stopOrderNOW) )
		stopOrderNOW  := getOrderDetails( stopOrderNOW.nowOrderNo )
}

/*
	Indicates whether Entry Order has status = complete
*/
isEntrySuccessful(){
	global
	
	return  IsObject( entryOrderNOW ) && entryOrderNOW.status == ORDER_STATUS_COMPLETE
}

/*
	Indicates whether Stop Order has status = complete
*/
isStopSuccessful(){
	global
	
	return  IsObject( stopOrderNOW ) && stopOrderNOW.status == ORDER_STATUS_COMPLETE
}

/*
	Indicates whether input order is in Order Book > Open Orders
*/
isOrderOpen( order ){	
	return IsObject(order) && order.status2 == "O"
}

/*
	Indicates whether input order is in Order Book > Completed Orders
*/
isOrderClosed( order ){
	return IsObject(order) && order.status2 == "C"
}

/*
	Returns true if entryOrderNOW is an object
*/
isEntryLinked(){
	global entryOrderNOW
	
	return IsObject( entryOrderNOW )
}

// ----------

/*
	Search order with input numbet in order array
*/
getOrderDetails_( list, orderno){
	Loop, % list.size {
		i := A_Index
		if( list[i].nowOrderNo ==  orderno ){					// Found
			return list[i]
		}	
	}
	return -1
}

/*
	Compare old and new order list and return First new order found 
*/
getNewOrder_( oldList, newList ){
	
	Loop, % newList.size {
		i 	  := A_Index	
		found := false
		
		Loop, % oldList.size {
			j := A_Index
			
			if( newList[i].nowOrderNo == oldList[j].nowOrderNo ){	
				found := true									// Found In old Order list
				break
			}
		}
		if( !found ){
			return newList[i]
		}
	}
	return -1
}

openOrderBook(){
	global
	
	IfWinExist,  %TITLE_ORDER_BOOK%
		return
	
	WinMenuSelectItem, %TITLE_NOW%,, Orders and Trades, Order Book		// open orderbook

	WinWait, %TITLE_ORDER_BOOK%
	WinMinimize, %TITLE_ORDER_BOOK%	
}

/*
	Parse Through Order book > open orders
*/
readOpenOrders(){
	global TITLE_ORDER_BOOK, OpenOrdersColumnIndex, OpenOrders
	
	openOrderBook()												// Open order book if not already opened	
	
	OpenOrders	    := {}
	OpenOrders.size := 0
	
	ControlGet, openOrdersRaw, List, , SysListView321, %TITLE_ORDER_BOOK%
		
	Loop, Parse, openOrdersRaw, `n  							// Extract our columns from table
	{															// Rows are delimited by linefeeds (`n)
		order := {} 											// Fields (columns) in each row are delimited by tabs (A_Tab)
		Loop, Parse, A_LoopField, %A_Tab%  									
		{				
			if( A_Index ==  OpenOrdersColumnIndex.orderType )
				order.orderType 	 := A_LoopField	
			else if( A_Index ==  OpenOrdersColumnIndex.buySell ) 
				order.buySell 	  	 := A_LoopField
			else if( A_Index ==  OpenOrdersColumnIndex.tradingSymbol ) 
				order.tradingSymbol := A_LoopField
			else if( A_Index ==  OpenOrdersColumnIndex.totalQty ) 
				order.totalQty 	 := A_LoopField
			else if( A_Index ==  OpenOrdersColumnIndex.pendingQty ) 
				order.pendingQty 	 := A_LoopField
			else if( A_Index ==  OpenOrdersColumnIndex.price ) 
				order.price 		 := A_LoopField
			else if( A_Index ==  OpenOrdersColumnIndex.triggerPrice ) 
				order.triggerPrice  := A_LoopField
			else if( A_Index ==  OpenOrdersColumnIndex.averagePrice ) 
				order.averagePrice  := A_LoopField
			else if( A_Index ==  OpenOrdersColumnIndex.status ) 
				order.status 		 := A_LoopField
			else if( A_Index ==  OpenOrdersColumnIndex.nowOrderNo ) 
				order.nowOrderNo 	 := A_LoopField
			else if( A_Index ==  OpenOrdersColumnIndex.nowUpdateTime ) 
				order.nowUpdateTime := A_LoopField
		}
		order.status2		:= "O"								// Is Order Open or Completed
		OpenOrders[A_Index] := order
		OpenOrders.size++	
	}
}

/*
	Parse Through Order book > completed orders
*/
readCompletedOrders(){
	global TITLE_ORDER_BOOK, CompletedOrdersColumnIndex, CompletedOrders
	
	openOrderBook()
		
	CompletedOrders	  	 := {}
	CompletedOrders.size := 0
	
	ControlGet, completedOrdersRaw, List, , SysListView322, %TITLE_ORDER_BOOK%
		
	Loop, Parse, completedOrdersRaw, `n
	{
		order := {}
		Loop, Parse, A_LoopField, %A_Tab%
		{
			if( A_Index ==  CompletedOrdersColumnIndex.orderType )
				order.orderType 	 := A_LoopField	
			else if( A_Index ==  CompletedOrdersColumnIndex.buySell ) 
				order.buySell 	  	 := A_LoopField
			else if( A_Index ==  CompletedOrdersColumnIndex.tradingSymbol ) 
				order.tradingSymbol  := A_LoopField
			else if( A_Index ==  CompletedOrdersColumnIndex.totalQty ) 
				order.totalQty 	     := A_LoopField
			else if( A_Index ==  CompletedOrdersColumnIndex.pendingQty ) 
				order.pendingQty 	 := A_LoopField
			else if( A_Index ==  CompletedOrdersColumnIndex.price ) 
				order.price 		 := A_LoopField
			else if( A_Index ==  CompletedOrdersColumnIndex.triggerPrice ) 
				order.triggerPrice   := A_LoopField
			else if( A_Index ==  CompletedOrdersColumnIndex.averagePrice ) 
				order.averagePrice   := A_LoopField
			else if( A_Index ==  CompletedOrdersColumnIndex.status ) 
				order.status 		 := A_LoopField
			else if( A_Index ==  CompletedOrdersColumnIndex.nowOrderNo ) 
				order.nowOrderNo 	 := A_LoopField
			else if( A_Index ==  CompletedOrdersColumnIndex.nowUpdateTime ) 
				order.nowUpdateTime := A_LoopField
			else if( A_Index ==  CompletedOrdersColumnIndex.rejectionReason ) 
				order.rejectionReason := A_LoopField			
		}
		order.status2			 := "C"	
		CompletedOrders[A_Index] := order
		CompletedOrders.size++
	}	
}

/*
	Reads Column Header text of Open and Completed Orders in orderbook to look for position of required fields 
*/
readColumnHeaders(){
	global	TITLE_ORDER_BOOK, OpenOrdersColumnIndex, CompletedOrdersColumnIndex
	
	openOrderBook()
	
	if( !IsObject(OpenOrdersColumnIndex) )
		OpenOrdersColumnIndex := {}	
	if( !IsObject(CompletedOrdersColumnIndex) )
		CompletedOrdersColumnIndex := {}	
	
// Open Orders
	// Read column header texts and extract position for columns that we need
	allHeaders  := GetExternalHeaderText( TITLE_ORDER_BOOK, "SysHeader321")		
	headers		:= ["Order Type", "Buy/Sell", "Trading Symbol", "Total Qty", "Pending Qty", "Price", "TriggerPrice", "Average Price", "Status", "NOWOrderNo", "NOW UpdateTime"]
	keys		:= ["orderType",  "buySell",  "tradingSymbol",  "totalQty",  "pendingQty",  "price", "triggerPrice", "averagePrice" , "status", "nowOrderNo", "nowUpdateTime"]			
	
	extractColumnIndices( "Order Book > Open Orders",  allHeaders, headers, OpenOrdersColumnIndex, keys )
	
// Completed Orders
	allHeaders  := GetExternalHeaderText( TITLE_ORDER_BOOK, "SysHeader322")
	headers		:= ["Order Type", "Buy/Sell", "Trading Symbol", "Total Qty", "Pending Qty", "Price", "TriggerPrice", "Average Price", "Status", "NOWOrderNo", "NOW UpdateTime", "Rejection Reason"]
	keys		:= ["orderType",  "buySell",  "tradingSymbol",  "totalQty",  "pendingQty",  "price", "triggerPrice", "averagePrice" , "status", "nowOrderNo", "nowUpdateTime", "rejectionReason"]
	
	extractColumnIndices( "Order Book > Completed Orders",  allHeaders, headers, CompletedOrdersColumnIndex, keys )	
}

/*
	listIdentifier= Identifier text for the List, used in error message
	allHeaders    = headers extracted from GetExternalHeaderText
	targetHeaders = Array of headers that we want to search in allHeaders
	targetObject  = Object to save positions with key taken from targetKeys and value = Column position
	Gives Error if Column is not found
*/
extractColumnIndices( listIdentifier, allHeaders, targetHeaders, targetObject, targetKeys  ){
	
	for index, headertext in allHeaders{
		Loop % targetHeaders.MaxIndex(){							// Loop through all needed columns and check if headertext is one of them 
			columnText	:= targetHeaders[A_Index]					// column we want
			key         := targetKeys[A_Index]						// key for OpenOrdersColumnIndex. Value = column position
			
			if( headertext ==  columnText ){						// column found, save index
				targetObject[key] := index
				break
			}
		}		
	}
	Loop % targetHeaders.MaxIndex(){								// Verify that all columns were found
		columnText	:= targetHeaders[A_Index]
		key         := targetKeys[A_Index]
	
		checkEmpty( targetObject[key], columnText, listIdentifier )
	}
}

/*
	If Column that we want is not found in header, show message and exit
*/
checkEmpty( value, field, listName ){
	global TITLE_ORDER_BOOK
	
	if( value == "" ){
		MsgBox, 262144,, Column %field% not found in %listName%
		WinClose, %TITLE_ORDER_BOOK%	
		Exit
	}
}

