WITH base_admissions AS (
  SELECT 
    p.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
    ON p.subject_id = adm.subject_id
  WHERE EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
    WHERE adm.hadm_id = icu.hadm_id
  )
),
base_with_ami_flag AS (
  SELECT 
    base.*,
    CASE WHEN diag.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_ami
  FROM base_admissions base
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      (icd_version = 9 AND icd_code LIKE '410%') OR
      (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
  ) diag 
    ON base.hadm_id = diag.hadm_id
  WHERE 
    base.age_at_admission BETWEEN 42 AND 52
    AND (SELECT gender FROM `physionet-data.mimiciv_3_1_hosp.patients` p WHERE p.subject_id = base.subject_id) = 'M'
),
ami_icu_stays AS (
  SELECT 
    icu.stay_id,
    icu.intime
  FROM base_with_ami_flag base
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu 
    ON base.hadm_id = icu.hadm_id
  WHERE base.is_ami = 1
),
procedures_in_window AS (
  SELECT 
    ami.stay_id,
    proc.itemid
  FROM ami_icu_stays ami
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc 
    ON ami.stay_id = proc.stay_id
  WHERE 
    proc.starttime BETWEEN ami.intime AND 
    DATETIME_ADD(ami.intime, INTERVAL 72 HOUR)
),
procedure_count_per_stay AS (
  SELECT 
    stay_id,
    COUNT(DISTINCT itemid) AS num_procedures
  FROM procedures_in_window
  GROUP BY stay_id
),
di_90 AS (
  SELECT 
    APPROX_QUANTILES(num_procedures, 100)[OFFSET(90)] AS di_90_percentile
  FROM procedure_count_per_stay
),
metrics AS (
  SELECT 
    AVG(CASE WHEN is_ami = 1 THEN DATETIME_DIFF(dischtime, admittime, DAY) ELSE NULL END) AS mean_los_ami,
    AVG(CASE WHEN is_ami = 0 THEN DATETIME_DIFF(dischtime, admittime, DAY) ELSE NULL END) AS mean_los_control,
    AVG(CASE WHEN is_ami = 1 THEN hospital_expire_flag ELSE NULL END) AS mortality_ami,
    AVG(CASE WHEN is_ami = 0 THEN hospital_expire_flag ELSE NULL END) AS mortality_control
  FROM base_with_ami_flag
)
SELECT 
  di_90_percentile,
  mean_los_ami,
  mean_los_control,
  mortality_ami,
  mortality_control
FROM di_90, metrics;