WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '411%' OR d.icd_code LIKE '412%' OR d.icd_code LIKE '413%' OR d.icd_code LIKE '414%'))
      OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I23%' OR d.icd_code LIKE 'I24%' OR d.icd_code LIKE 'I25%'))
    )
),

first_troponin AS (
  SELECT
    l.subject_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE d.label LIKE '%Troponin%'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0
)

SELECT
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) AS median,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS iqr
FROM first_troponin ft
JOIN eligible_patients ep ON ft.subject_id = ep.subject_id
WHERE ft.rn = 1
  AND ft.valuenum > 0.014;