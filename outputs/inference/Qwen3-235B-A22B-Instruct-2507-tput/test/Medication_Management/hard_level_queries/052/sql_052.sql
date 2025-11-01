WITH hhs_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    (icd_version = 10 AND icd_code IN ('E1101', 'E1301'))  -- HHS codes
  )
),
hhs_patients AS (
  SELECT adm.hadm_id, adm.subject_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag,
         p.gender, p.anchor_age, p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON adm.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON adm.hadm_id = diag.hadm_id
  JOIN hhs_icd ON diag.icd_code = hhs_icd.icd_code
  WHERE diag.icd_version = 10
    AND p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 68 AND 78
),
meds_72h AS (
  SELECT h.hadm_id,
         COUNT(DISTINCT pr.drug) AS num_medications,
         COUNT(CASE WHEN LOWER(pr.drug) IN (
             'spironolactone', 'amiloride', 'triamterene', 'eplerenone',
             'lisinopril', 'enalapril', 'ramipril', 'captopril', 'benazepril',  -- ACEi
             'losartan', 'valsartan', 'irbesartan', 'candesartan', 'olmesartan', -- ARBs
             'potassium chloride', 'k-dur', 'klor-con',
             'ibuprofen', 'naproxen', 'celecoxib', 'diclofenac'  -- NSAIDs
           ) THEN 1 END) AS high_risk_drug_count
  FROM hhs_patients h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON h.hadm_id = pr.hadm_id
    AND pr.starttime >= h.admittime
    AND pr.starttime <= h.admittime + INTERVAL '72' HOUR
  GROUP BY h.hadm_id
),
los_mortality AS (
  SELECT hadm_id,
         hospital_expire_flag,
         (DATETIME_DIFF(dischtime, admittime, SECOND) / (24*60*60.0)) AS los_days
  FROM hhs_patients
)
SELECT
  -- 72-hour medication complexity: median and IQR
  APPROX_QUANTILES(num_medications, 100)[OFFSET(50)] AS med_num_meds_72h,
  APPROX_QUANTILES(num_medications, 100)[OFFSET(25)] AS q1_num_meds_72h,
  APPROX_QUANTILES(num_medications, 100)[OFFSET(75)] AS q3_num_meds_72h,
  -- Percent of patients with >=2 high-risk drugs for hyperkalemia
  AVG(CASE WHEN high_risk_drug_count >= 2 THEN 1.0 ELSE 0.0 END) * 100 AS pct_high_risk_interactions,
  -- Top-quartile (75th percentile) of hospital LOS
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75th_percentile_days,
  -- Hospital mortality rate
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate_percent
FROM meds_72h
JOIN los_mortality lm ON meds_72h.hadm_id = lm.hadm_id;