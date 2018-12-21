
// Reports.java --
//
// Reports.java is part of ElectricCommander.
//
// Copyright (c) 2005-2012 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import org.jetbrains.annotations.NonNls;

import com.google.gwt.user.client.ui.Anchor;
import com.google.gwt.user.client.ui.DecoratorPanel;
import com.google.gwt.user.client.ui.HTML;
import com.google.gwt.user.client.ui.Label;
import com.google.gwt.user.client.ui.VerticalPanel;
import com.google.gwt.user.client.ui.Widget;

import com.electriccloud.commander.client.domain.Property;
import com.electriccloud.commander.client.domain.PropertySheet;
import com.electriccloud.commander.client.requests.GetPropertiesRequest;
import com.electriccloud.commander.client.responses.CommanderError;
import com.electriccloud.commander.client.responses.PropertySheetCallback;
import com.electriccloud.commander.gwt.client.ComponentBase;
import com.electriccloud.commander.gwt.client.protocol.xml.RequestSerializerImpl;
import com.electriccloud.commander.gwt.client.ui.FormTable;
import com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder;

import static com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder.createUrl;

/**
 */
public class Reports
    extends ComponentBase
{

    //~ Methods ----------------------------------------------------------------

    @Override public Widget doInit()
    {

        /* Renders the component. */
        DecoratorPanel rootPanel = new DecoratorPanel();
        VerticalPanel  vPanel    = new VerticalPanel();

        vPanel.setBorderWidth(0);

        String              jobId      = getGetParameter("jobId");
        CommanderUrlBuilder urlBuilder = createUrl("jobDetails.php")
                .setParameter("jobId", jobId);

        // noinspection HardCodedStringLiteral,StringConcatenation
        vPanel.add(new Anchor("Job: " + jobId, urlBuilder.buildString()));

        Widget htmlH1 = new HTML("<h1>Perforce Changelog</h1>");

        vPanel.add(htmlH1);

        Widget htmlLabel = new HTML(
                "<p><b>Perforce changelogs associated with the ElectricCommander job:</b></p>");

        vPanel.add(htmlLabel);

        FormTable formTable = getUIFactory().createFormTable();

        callback("ecscm_changeLogs", formTable);
        vPanel.add(formTable.getWidget());
        rootPanel.add(vPanel);

        return rootPanel;
    }

    private void callback(
            @NonNls String  propertyName,
            final FormTable formTable)
    {
        String jobId = getGetParameter("jobId");

        if (getLog().isDebugEnabled()) {
            getLog().debug("this is getGetParameter for jobId: "
                    + getGetParameter("jobId"));
            getLog().debug("this is jobId: " + jobId);
        }

        GetPropertiesRequest req = getRequestFactory()
                .createGetPropertiesRequest();

        req.setPath("/jobs/" + jobId + "/" + propertyName);

        if (getLog().isDebugEnabled()) {
            getLog().debug(
                "p4 Reports doInit: setting up getProperties command request");
        }

        req.setCallback(new PropertySheetCallback() {
                @Override public void handleResponse(PropertySheet response)
                {
                    parseResponse(response, formTable);
                }

                @Override public void handleError(CommanderError error)
                {

                    if (getLog().isDebugEnabled()) {
                        getLog().debug("Error trying to access property");
                    }

                    // noinspection HardCodedStringLiteral
                    formTable.addRow("0", new Label("No changelogs Found"));
                }
            });

        if (getLog().isDebugEnabled()) {
            getLog().debug("p4 Reports doInit: Issuing Commander request: "
                    + new RequestSerializerImpl().serialize(req));
        }

        doRequest(req);
    }

    private void parseResponse(
            PropertySheet response,
            FormTable     form)
    {

        if (getLog().isDebugEnabled()) {
            getLog().debug("getProperties request returned "
                    + response.getProperties()
                              .size() + " properties");
        }

        for (Property p : response.getProperties()
                                  .values()) {
            HTML htmlH1 = new HTML("<h3>" + p.getName() + "</h3> <pre>"
                        + p.getValue() + "</pre>");

            form.addRow("0", htmlH1);

            if (getLog().isDebugEnabled()) {
                getLog().debug("  propertyName="
                        + p.getName()
                        + ", value=" + p.getValue());
            }
        }
    }
}
