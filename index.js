import mtp from "md-to-pdf";

mtp("./README.md", { dest: "README.pdf" }).then(() => {
    console.log("mtp Done");
});
