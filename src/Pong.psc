component CPong (in  active  uint:4  iKeys   /*$ Default */,
				 in  active  uint:12 iColumn /*$ Default */,
			 	 in  passive uint:12 iLine   /*$ Default */,
				 out passive ubyte   oR      /*$ Default */,
				 out passive ubyte   oG      /*$ Default */,
				 out passive ubyte   oB      /*$ Default */)
{
    // Constants
    const int cWidth           = g_is_fpga_target * 576 + 64; // 640 or 64
    const int cHeight          = g_is_fpga_target * 432 + 48; // 480 or 48
    const int cBallSize        = g_is_fpga_target * 12  + 4;  // 16  or 4
    const int cHalfBallSize    = g_is_fpga_target * 6   + 2;  // 8   or 2
    const int cBorderWidth     = g_is_fpga_target * 5   + 3;  // 8   or 3
    const int cPaddleWidth     = g_is_fpga_target * 110 + 10; // 120 or 10
    const int cPaddleHeight    = g_is_fpga_target * 7   + 3;  // 10 or 3
    
    const int cPaddlePositionY = cHeight - (g_is_fpga_target * 54 + 10); // 416 or 38
    const int cPaddleLimitX    = cWidth  - cPaddleWidth;

    // Decoded keys
    temp bit tRight = bit(iKeys, 1ub);
    temp bit tLeft  = bit(iKeys, 2ub);

    // Counts at 25MHz (Pixel clock) 
    // Bit "n" toggles at 25MHz divided by 2^n
    uint:20 SyncTimer;

    // Synchronisation for paddle and ball update
    temp bit tUpdatePaddleNormal  = bits(SyncTimer, 15ub, 0ub) == (uint:20)0;
    temp bit tUpdateBallNormal    = bits(SyncTimer, 15ub, 0ub) == (uint:20)0;
    temp bit tUpdatePaddleMiniSim = bits(SyncTimer, 9ub, 0ub)  == (uint:20)0;  
    temp bit tUpdateBallMiniSim   = bits(SyncTimer, 10ub, 0ub) == (uint:20)0;  

    // Update period depends whether the target is simulation or fpga and the value pUseMiniVga
    temp bit tUpdatePaddle = (g_is_fpga_target)?(tUpdatePaddleNormal):(tUpdatePaddleMiniSim);
    temp bit tUpdateBall   = (g_is_fpga_target)?(tUpdateBallNormal)  :(tUpdateBallMiniSim);

    // Position and direction of the ball
    uint:10 BallX;
    uint:9  BallY;
    int:2   BallDirX;  // Right +1, Left -1
    int:2   BallDirY;  // Down  +1, Up   -1

    // Position of the paddle
    uint:10 PaddlePositionX;

    // Pixel is in the ball
    temp bit tBall = (iColumn >= BallX) && (iColumn < BallX + cBallSize) 
                  && (iLine   >= BallY) && (iLine   < BallY + cBallSize);

    // Pixel is in the border
    temp bit tBorder = (iColumn < cBorderWidth)
                    || (iColumn >= cWidth - cBorderWidth)
                    || (iLine   < cBorderWidth)
                    || (iLine   >= cHeight - cBorderWidth);

    // Pixel is in the paddle
    temp bit tPaddle = (iColumn >= (PaddlePositionX)) 
                    && (iColumn <  (PaddlePositionX + cPaddleWidth))
                    && (iLine   >= (cPaddlePositionY))
                    && (iLine   <  (cPaddlePositionY + cPaddleHeight));

    // Pixel touches a bouncing object
    temp bit tBouncingObject = tBorder || tPaddle;

    // Background: red checkboard                 
    temp bit tBackground = (bit(iColumn, 3ub) ^ bit(iLine, 3ub));    

    // Color                 
    temp bit tR = tBouncingObject | tBall | tBackground;
    temp bit tG = tBouncingObject | tBall;
    temp bit tB = tBouncingObject | tBall;

    ProcessPixel(0) on iColumn
    {
        // Everything is synchronize with the pixel clock event
        SyncTimer++;

        //----- Collision detection
        if (tBouncingObject)
        {   // The pixel address falls onto one of the bouncing object
            // Cheks if it also touches one of the wall sides
            //     and change ball direction
            if ((iColumn == BallX) && (iLine == (BallY + cHalfBallSize)))
            {   // Collision left
                BallDirX = (int:2)1;
            }
            if ((iColumn == (BallX + cBallSize)) && (iLine == (BallY + cHalfBallSize)))
            {   // Collision right
                BallDirX = (int:2)-1;
            }
            if ((iLine == BallY) && (iColumn == (BallX + cHalfBallSize)))
            {   // Collision top
                BallDirY = (int:2)1;
            }
            if ((iLine == (BallY + cBallSize)) && (iColumn == (BallX + cHalfBallSize)))
            {   // Collision bottom
                BallDirY = (int:2)-1;
            }
        }

        //----- Update paddle position
        if (tUpdatePaddle)
        {   
            if (tRight && PaddlePositionX < cPaddleLimitX)
            {
                PaddlePositionX++;
            }
            if (tLeft && PaddlePositionX > 0)
            {
                PaddlePositionX--;
            }
        }

        //----- Update ball position
        if (tUpdateBall)
        {
            if(g_is_fpga_target)  // Since pMiniVga is a constant, it's like a #ifdefine
            {
                BallX = (uint:10)(BallX + BallDirX);
                BallY = (uint:9) (BallY + BallDirY);
            }
            else
            {
                if(BallX >= cWidth)  
                {   // Bring back in middle
                    BallX = (uint:10)(cWidth >> 2);
                }
                else
                {
                    BallX = (uint:10)(BallX + BallDirX);
                }
                if(BallY >= cHeight)  
                {   // Bring back in middle
                    BallY = (uint:9)(cHeight >> 2);
                }
                else
                {
                    BallY = (uint:9) (BallY + BallDirY);
                }
            }
        }

        //----- Color management
        if(g_is_fpga_target)  // Since pMiniVga is a constant, it's like a #ifdefine
        {
            oR = (uint:8)((tR) ? (255) : (0));
            oG = (uint:8)((tG) ? (255) : (0));
            oB = (uint:8)((tB) ? (255) : (0));
        }
        else
        {
            if((iLine < cHeight) && (iColumn < cWidth))
            {
                oR = (uint:8)((tR) ? (255) : (0));
                oG = (uint:8)((tG) ? (255) : (0));
                oB = (uint:8)((tB) ? (255) : (0));
            }
            else
            {   // Black elsewhere
                oR = 0ub;
                oG = 0ub;
                oB = 0ub;
            }
        }
    }
};