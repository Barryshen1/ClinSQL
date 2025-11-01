WITH InstabilityScore AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    -- Calculate instability score based on vital signs
    (
      CASE WHEN ce.itemid = 220177 THEN 1 ELSE 0 END + -- Heart Rate
      CASE WHEN ce.itemid = 220188 THEN 1 ELSE 0 END + -- Systolic Blood Pressure
      CASE WHEN ce.itemid = 220191 THEN 1 ELSE 0 END + -- Diastolic Blood Pressure
      CASE WHEN ce.itemid = 220193 THEN 1 ELSE 0 END + -- Mean Arterial Pressure
      CASE WHEN ce.itemid = 220195 THEN 1 ELSE 0 END + -- Respiratory Rate
      CASE WHEN ce.itemid = 220197 THEN 1 ELSE 0 END + -- SpO2
      CASE WHEN ce.itemid = 220199 THEN 1 ELSE 0 END + -- Temperature
      CASE WHEN ce.itemid = 220201 THEN 1 ELSE 0 END + -- Urine Output
      CASE WHEN ce.itemid = 220203 THEN 1 ELSE 0 END + -- Glasgow Coma Scale
      CASE WHEN ce.itemid = 220205 THEN 1 ELSE 0 END + -- Pain Score
      CASE WHEN ce.itemid = 220207 THEN 1 ELSE 0 END + -- Blood Glucose
      CASE WHEN ce.itemid = 220209 THEN 1 ELSE 0 END + -- Lactate
      CASE WHEN ce.itemid = 220211 THEN 1 ELSE 0 END + -- Creatinine
      CASE WHEN ce.itemid = 220213 THEN 1 ELSE 0 END + -- BUN
      CASE WHEN ce.itemid = 220215 THEN 1 ELSE 0 END + -- Troponin I
      CASE WHEN ce.itemid = 220217 THEN 1 ELSE 0 END + -- Troponin T
      CASE WHEN ce.itemid = 220219 THEN 1 ELSE 0 END + -- WBC Count
      CASE WHEN ce.itemid = 220221 THEN 1 ELSE 0 END + -- Hemoglobin
      CASE WHEN ce.itemid = 220223 THEN 1 ELSE 0 END + -- Platelet Count
      CASE WHEN ce.itemid = 220225 THEN 1 ELSE 0 END + -- INR
      CASE WHEN ce.itemid = 220227 THEN 1 ELSE 0 END + -- PTT
      CASE WHEN ce.itemid = 220229 THEN 1 ELSE 0 END + -- Sodium
      CASE WHEN ce.itemid = 220231 THEN 1 ELSE 0 END + -- Potassium
      CASE WHEN ce.itemid = 220233 THEN 1 ELSE 0 END + -- Chloride
      CASE WHEN ce.itemid = 220235 THEN 1 ELSE 0 END + -- Bicarbonate
      CASE WHEN ce.itemid = 220237 THEN 1 ELSE 0 END + -- Phosphate
      CASE WHEN ce.itemid = 220239 THEN 1 ELSE 0 END + -- Magnesium
      CASE WHEN ce.itemid = 220241 THEN 1 ELSE 0 END + -- Calcium
      CASE WHEN ce.itemid = 220243 THEN 1 ELSE 0 END + -- Total Protein
      CASE WHEN ce.itemid = 220245 THEN 1 ELSE 0 END + -- Albumin
      CASE WHEN ce.itemid = 220247 THEN 1 ELSE 0 END + -- Bilirubin
      CASE WHEN ce.itemid = 220249 THEN 1 ELSE 0 END + -- AST
      CASE WHEN ce.itemid = 220251 THEN 1 ELSE 0 END + -- ALT
      CASE WHEN ce.itemid = 220253 THEN 1 ELSE 0 END + -- Alkaline Phosphatase
      CASE WHEN ce.itemid = 220255 THEN 1 ELSE 0 END + -- Creatine Kinase
      CASE WHEN ce.itemid = 220257 THEN 1 ELSE;