
// ReportsFactory.java --
//
// ReportsFactory.java is part of ElectricCommander.
//
// Copyright (c) 2005-2011 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import com.electriccloud.commander.gwt.client.Component;
import com.electriccloud.commander.gwt.client.ComponentBaseFactory;
import com.electriccloud.commander.gwt.client.ComponentContext;
import org.jetbrains.annotations.NotNull;

/**
 * This factory is responsible for providing instances of the reports class.
 */
public class ReportsFactory
    extends ComponentBaseFactory
{

    //~ Methods ----------------------------------------------------------------

    @NotNull
    @Override public Component createComponent(ComponentContext jso)
    {
        return new Reports();
    }
}
