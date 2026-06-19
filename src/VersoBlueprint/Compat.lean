/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual

namespace Verso

class MonadReportError (m : Type → Type) where
  reportError : String → m Unit

def reportError [MonadReportError m] (text : String) : m Unit :=
  MonadReportError.reportError text

instance [Monad m] [MonadLiftT IO m] [MonadReaderOf Genre.Manual.TraverseContext m] :
    MonadReportError m where
  reportError := Genre.Manual.logError

instance [Monad m] : MonadReportError (Doc.Html.HtmlT genre m) where
  reportError := Doc.Html.HtmlT.logError

instance [Monad m] : MonadReportError (Doc.TeX.TeXT genre m) where
  reportError := Doc.TeX.logError

end Verso
