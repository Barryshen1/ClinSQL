WITH ACS_admissions AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE (
        (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '411%' OR di.icd_code LIKE '412%' OR di.icd_code LIKE '413%' OR di.icd_code LIKE '414%'))
        OR
        (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I20.0%' OR di.icd_code LIKE 'I24%'))
      )
),
first_troponin AS (
  SELECT le.hadm_id, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  WHERE (LOWER(dli.label) LIKE '%troponin%t%' OR LOWER(dli.label) LIKE '%troponin t%')
    AND le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) = 1
)
SELECT
  CASE
    WHEN ft.valuenum <= 0.04 THEN 'Normal'
    WHEN ft.valuenum > 0.04 AND ft.valuenum <= 0.1 THEN 'Borderline'
    WHEN ft.valuenum > 0.1 THEN 'Elevated'
  END AS troponin_category,
  COUNT(*) AS admission_count
FROM ACS_admissions a
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON a.hadm_id = adm.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
JOIN first_troponin ft ON a.hadm_id = ft.hadm_id
WHERE p.gender = 'M'
  AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 79 AND 89
GROUP BY troponin_category
ORDER BY troponin_category;