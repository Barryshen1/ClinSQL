WITH male_acs AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND (
      (di.icd_version = 10 
       AND (di.icd_code = 'I20.0' OR di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
      OR
      (di.icd_version = 9 
       AND (di.icd_code LIKE '410%' OR di.icd_code = '411.1'))
    )
),
peaks AS (
  SELECT ma.hadm_id, MAX(le.valuenum) AS peak_troponin
  FROM male_acs ma
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON ma.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON le.hadm_id = a.hadm_id
  WHERE le.itemid IN (50586, 51006)
    AND le.valuenum IS NOT NULL
    AND le.charttime >= a.admittime
    AND le.charttime <= a.dischtime
  GROUP BY ma.hadm_id
  HAVING peak_troponin IS NOT NULL
)
SELECT
  APPROX_QUANTILES(peak_troponin, 100)[OFFSET(75)] AS p75_peak_troponin
FROM peaks;