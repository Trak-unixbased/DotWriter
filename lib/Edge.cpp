#include "Edge.h"
#include "Node.h"
#include "Graph.h"

#include <ostream>

namespace DotWriter {

Edge::Edge(Node * src, Node * dst, const std::string &label, bool is_html_label) :
  _src(src), _dst(dst), _label(label), _is_html_label(is_html_label)
{}

Edge::Edge(Node * src, Node * dst, const std::string &label) :
  Edge(src, dst, label, false)
{}

Edge::Edge(Node * src, Node * dst, const HtmlString &label) :
  Edge(src, dst, static_cast<std::string>(label), true)
{}

void Edge::Print(bool isDirected, std::ostream& out) {
  out << _src->GetId() << (isDirected ? "->" : "--") << _dst->GetId();

  if (_label.compare("") != 0) {
    if (_is_html_label) {
      _attributes.AddHtmlLabel(_label);
    } else {
      _attributes.AddCustomAttribute("label", _label);
    }
  }

  if (!_attributes.Empty()) {
    out << " [";
    _attributes.Print(out);
    out << "]";
  }

  out << ";\n";
}

}  // namespace DotWriter
