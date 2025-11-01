WITH ami_flag AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' THEN 1 ELSE 0 END) AS has_ami
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
base AS (
  SELECT 
    icu.stay_id,
    icu.hadm_id,
    icu.intime,
    icu.outtime,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.subject_id,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
    COALESCE(ami.has_ami, 0) AS has_ami
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  LEFT JOIN ami_flag ami
    ON adm.hadm_id = ami.hadm_id
  WHERE 
    pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 42 AND 52
),
procedures AS (
  SELECT 
    b.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM base b
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON b.stay_id = pe.stay_id
    AND pe.starttime >= b.intime
    AND pe.starttime <= b.intime + INTERVAL '72' HOUR
  GROUP BY b.stay_id
)
SELECT 
  (SELECT APPROX_QUANTILES(procedure_count, 100)[OFFSET(90)] 
   FROM procedures p
   INNER JOIN base b ON p.stay_id = b.stay_id
   WHERE b.has_ami = 1) AS ami_diagnostic_intensity_90th,

  (SELECT AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0)
   FROM base
   WHERE has_ami = 1) AS ami_mean_los,

  (SELECT AVG(hospital_expire_flag)
   FROM base
   WHERE has_ami = 1) AS ami_mortality,

  (SELECT AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0)
   FROM base
   WHERE has_ami = 0) AS control_mean_los,

  (SELECT AVG(hospital_expire_flag)
   FROM base
   WHERE has_ami = 0) AS control_mortality;