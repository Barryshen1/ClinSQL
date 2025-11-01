WITH stroke_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age = 94
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '433%') OR
      (di.icd_version = 9 AND di.icd_code LIKE '434%') OR
      (di.icd_version = 9 AND di.icd_code = '436') OR
      (di.icd_version = 10 AND di.icd_code LIKE 'I63%')
    )
),
glucose_vals AS (
  SELECT l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN stroke_admissions sa
    ON l.hadm_id = sa.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON sa.hadm_id = a.hadm_id
  WHERE l.itemid = 50931  -- Serum glucose
    AND l.valuenum IS NOT NULL
    AND DATE(l.charttime) = DATE(a.dischtime)
)
SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS q25,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS q75
FROM glucose_vals;