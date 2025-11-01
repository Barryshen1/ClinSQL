WITH 
patients_filtered AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
),
acs_admissions AS (
  SELECT 
    df.hadm_id
  FROM patients_filtered df
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON df.hadm_id = diag.hadm_id AND df.subject_id = diag.subject_id
  WHERE diag.seq_num = 1
    AND diag.icd_code IN (
      'I200', 'I210', 'I211', 'I212', 'I213', 'I214',
      'I220', 'I221', 'I222', 'I228', 'I229',
      'I240', 'I241', 'I248', 'I249'
    )
),
admission_period AS (
  SELECT 
    hadm_id,
    COALESCE(edregtime, admittime) AS admission_start,
    dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
initial_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    le.valueuom,
    ROW_NUMBER() OVER (
      PARTITION BY le.hadm_id 
      ORDER BY le.charttime ASC
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  INNER JOIN admission_period ap
    ON le.hadm_id = ap.hadm_id
  WHERE dli.label = 'Troponin T, high sensitivity'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= ap.admission_start
    AND le.charttime <= ap.dischtime
),
troponin_ngmL AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN valueuom = 'ng/L' THEN valuenum / 1000.0
      WHEN valueuom = 'ng/mL' THEN valuenum
      ELSE NULL 
    END AS value_ngmL
  FROM initial_troponin
  WHERE rn = 1
    AND valueuom IN ('ng/L', 'ng/mL')
),
filtered_values AS (
  SELECT 
    value_ngmL
  FROM acs_admissions aa
  INNER JOIN troponin_ngmL tn
    ON aa.hadm_id = tn.hadm_id
  WHERE tn.value_ngmL > 0.014  -- ULN = 0.014 ng/mL
)
SELECT 
  APPROX_QUANTILES(value_ngmL, 1000)[OFFSET(500)] AS median,
  APPROX_QUANTILES(value_ngmL, 1000)[OFFSET(750)] - APPROX_QUANTILES(value_ngmL, 1000)[OFFSET(250)] AS iqr
FROM filtered_values;