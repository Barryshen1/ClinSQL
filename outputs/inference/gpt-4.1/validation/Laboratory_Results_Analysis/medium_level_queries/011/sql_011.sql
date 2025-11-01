WITH male_61_71 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 61 AND 71
),
chest_pain_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN male_61_71 pat ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    -- ICD-10 chest pain codes
    (diag.icd_version = 10 AND diag.icd_code IN ('R071', 'R072', 'R0789', 'R079'))
    -- ICD-9 chest pain codes
    OR (diag.icd_version = 9 AND diag.icd_code IN ('78650', '78651', '78652', '78659'))
),
hs_tnt_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND (LOWER(label) LIKE '%high%' OR LOWER(label) LIKE '%hs%')
),
initial_hs_tnt AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    labe.itemid,
    labe.charttime,
    labe.valuenum,
    labe.valueuom
  FROM chest_pain_admissions adm
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` labe
    ON adm.subject_id = labe.subject_id AND adm.hadm_id = labe.hadm_id
  JOIN hs_tnt_items hs ON labe.itemid = hs.itemid
  WHERE labe.valuenum IS NOT NULL
),
first_hs_tnt_per_admission AS (
  SELECT
    subject_id,
    hadm_id,
    valueuom,
    MIN(charttime) AS first_charttime
  FROM initial_hs_tnt
  GROUP BY subject_id, hadm_id, valueuom
),
first_hs_tnt_value AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.valuenum,
    i.valueuom
  FROM initial_hs_tnt i
  JOIN first_hs_tnt_per_admission f
    ON i.subject_id = f.subject_id
    AND i.hadm_id = f.hadm_id
    AND i.charttime = f.first_charttime
    AND i.valueuom = f.valueuom
),
categorized_hs_tnt AS (
  SELECT
    subject_id,
    hadm_id,
    -- Convert to ng/L if needed
    CASE
      WHEN LOWER(valueuom) = 'ng/ml' THEN valuenum * 1000
      ELSE valuenum
    END AS hs_tnt_ngl,
    CASE
      WHEN
        (LOWER(valueuom) = 'ng/ml' AND valuenum * 1000 < 14)
        OR (LOWER(valueuom) = 'ng/l' AND valuenum < 14)
      THEN 'Normal'
      WHEN
        ((LOWER(valueuom) = 'ng/ml' AND valuenum * 1000 >= 14 AND valuenum * 1000 <= 52)
        OR (LOWER(valueuom) = 'ng/l' AND valuenum >= 14 AND valuenum <= 52))
      THEN 'Borderline'
      WHEN
        (LOWER(valueuom) = 'ng/ml' AND valuenum * 1000 > 52)
        OR (LOWER(valueuom) = 'ng/l' AND valuenum > 52)
      THEN 'Myocardial injury'
      ELSE 'Unknown'
    END AS hs_tnt_category
  FROM first_hs_tnt_value
)
SELECT
  hs_tnt_category AS category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percent
FROM categorized_hs_tnt
WHERE hs_tnt_category IN ('Normal', 'Borderline', 'Myocardial injury')
GROUP BY hs_tnt_category
ORDER BY percent DESC;