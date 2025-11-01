WITH amipatients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND LOWER(did.long_title) LIKE '%acute myocardial infarction%'
),
first_hstnt AS (
  SELECT
    ap.hadm_id,
    le.valuenum,
    le.valueuom,
    ROW_NUMBER() OVER (PARTITION BY ap.hadm_id ORDER BY le.charttime) AS rn
  FROM amipatients ap
  INNER JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON ap.hadm_id = le.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%hs-tnt%'
    OR LOWER(dl.label) LIKE '%high sensitivity troponin t%'
    OR LOWER(dl.label) LIKE '%hs troponin t%'
    OR LOWER(dl.label) LIKE '%hs troponin%'
    OR LOWER(dl.label) LIKE '%troponin t hs%'
    OR LOWER(dl.label) LIKE '%troponin t high sensitivity%'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/L'  -- Ensure unit is ng/L for standard thresholds
)
SELECT
  CASE
    WHEN valuenum < 14 THEN 'Normal'
    WHEN valuenum BETWEEN 14 AND 39 THEN 'Borderline'
    WHEN valuenum >= 40 THEN 'Myocardial Injury'
    ELSE 'Unknown'
  END AS hstnt_category,
  COUNT(*) AS count,
  ROUND(
    COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
    2
  ) AS percentage
FROM first_hstnt
WHERE rn = 1
GROUP BY hstnt_category
ORDER BY hstnt_category;