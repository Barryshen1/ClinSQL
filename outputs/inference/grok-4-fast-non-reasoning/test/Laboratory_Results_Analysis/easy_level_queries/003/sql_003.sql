WITH acs_admissions AS (
  -- Identify male, ~64yo ACS admissions (using calculated admission age)
  SELECT DISTINCT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND -- Approximate admission age ~64 (anchor_age is age at 2008 anchor)
        (DATE_DIFF(a.admittime, DATE('1900-01-01'), YEAR) - p.anchor_age) BETWEEN 63 AND 65
    AND EXTRACT(YEAR FROM a.admittime) >= p.anchor_year  -- Post-anchor admissions only
    AND (
      (d.icd_version = '10' AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%'))
      OR 
      (d.icd_version = '9' AND d.icd_code LIKE '410%')
    )
    AND a.hospital_expire_flag = 0  -- Focus on discharges (excludes in-hospital deaths)
),
troponin_peaks AS (
  -- Extract peak troponin per ACS admission
  SELECT 
    a.hadm_id,
    MAX(l.valuenum) AS peak_troponin
  FROM acs_admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
  WHERE l.charttime >= a.admittime
    AND l.charttime <= COALESCE(a.deathtime, a.dischtime)
    AND REGEXP_CONTAINS(LOWER(li.label), r'troponin')
    AND l.valueuom IN ('ng/mL', 'ng/ml')
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0
    AND (l.flag IS NULL OR l.flag = '')
  GROUP BY a.hadm_id
  HAVING peak_troponin IS NOT NULL  -- Ensure valid peak
)
-- Compute 75th percentile of peaks
SELECT 
  PERCENTILE_CONT(0.75) OVER() AS p75_peak_troponin
FROM troponin_peaks;