const e = React.createElement;

function TranslatablePageHeader({title, subTitle, t}) {
  return e(
    "div",
    {
      id: "header", // used to ease targetting of DOM elements in automated tests
      className: "page-header"
    },
    e(
      "div",
      {
        className: "page-header__logo"
      },
      e(
        "img",
        {
          className: "page-header__logo__image",
          src: "../../logo.png",
          alt: t("election_server"),
          title: t("election_server")
        }
      )
    ),
    e(
      "div",
      {
        className: "page-header__titles"
      },
      e(
        "h1",
        {
          className: "page-header__titles__election-name",
          id: "election_name",
        },
        txt_br(title)
      ),
      e(
        "p",
        {
          className: "page-header__titles__election-description",
          id: "election_description"
        },
        txt_br(subTitle)
      )
    ),
    e(
      "div",
      {
        className: "page-header__right"
      }
    )
  );
}

TranslatablePageHeader.defaultProps = {
  title: "Title of election",
  subTitle: "Subtitle of election",
  logoAlt: "Election server"
};

const PageHeader = ReactI18next.withTranslation()(TranslatablePageHeader);

export { PageHeader, TranslatablePageHeader };
export default PageHeader;
