WITH ami_admissions AS (
  -- Identify admissions with AMI diagnosis
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE REGEXP_CONTAINS(d.icd_code, r'^(I21|410)')
),

eligible_patients AS (
  -- Filter male patients aged 76–86 with AMI
  SELECT p.subject_id, p.anchor_age, a.hadm_id, a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN ami_admissions ami
    ON a.hadm_id = ami.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
),

icu_stays_with_procs AS (
  -- Get ICU stays and count distinct procedures in first 24 hours
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los AS icu_los,
    ep.hospital_expire_flag,
    COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN eligible_patients ep
    ON icu.hadm_id = ep.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON icu.stay_id = pe.stay_id
    AND pe.starttime >= icu.intime
    AND pe.starttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id, icu.los, ep.hospital_expire_flag
),

quartiled_data AS (
  -- Stratify into quartiles by distinct procedure count
  SELECT *,
    NTILE(4) OVER (ORDER BY distinct_procedure_count) AS quartile
  FROM icu_stays_with_procs
)

-- Final aggregation by quartile
SELECT
  quartile,
  AVG(distinct_procedure_count) AS mean_procedure_count,
  AVG(icu_los) AS mean_icu_los,
  100 * AVG(hospital_expire_flag) AS hospital_mortality_percent
FROM quartiled_data
GROUP BY quartile
ORDER BY quartile;