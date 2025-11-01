WITH asthma_admissions AS (
  SELECT
    diag.subject_id,
    diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dcd
    ON diag.icd_code = dcd.icd_code AND diag.icd_version = dcd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON diag.subject_id = adm.subject_id AND diag.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE LOWER(dcd.long_title) LIKE '%asthma%'
    AND pat.gender = 'M'
    -- Age at admission: anchor_age + (adm year - anchor_year)
    AND (pat.anchor_age +
         (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 77 AND 87
)

-- 2) For each admission, identify the first ICU stay (earliest intime)
, icu_first AS (
  SELECT
    aa.subject_id,
    aa.hadm_id,
    i.stay_id AS first_stay_id,
    i.intime AS first_intime
  FROM asthma_admissions AS aa
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON aa.subject_id = i.subject_id
   AND aa.hadm_id = i.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY aa.subject_id, aa.hadm_id ORDER BY i.intime) = 1
)

-- 3) Compute 72-hour ICU procedure burden for the first ICU stay
, proc_72h AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.first_stay_id,
    f.first_intime,
    COUNT(*) AS proc_count_72h
  FROM icu_first AS f
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON pe.subject_id = f.subject_id
   AND pe.hadm_id = f.hadm_id
   AND pe.stay_id = f.first_stay_id
  WHERE pe.starttime >= f.first_intime
    AND pe.starttime < TIMESTAMP_ADD(f.first_intime, INTERVAL 72 HOUR)
  GROUP BY
    f.subject_id, f.hadm_id, f.first_stay_id, f.first_intime
)

-- 4) Get hospital LOS and mortality for each admission
, admit_stats AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS hospital_los_days,
    a.hospital_expire_flag AS mortality
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN asthma_admissions AS aa
    ON a.subject_id = aa.subject_id
   AND a.hadm_id = aa.hadm_id
)

-- 5) Combine and compute quartiles
SELECT
  quartile AS quartile_number,
  AVG(proc_count_72h) AS mean_proc_count_72h,
  AVG(hospital_los_days) AS mean_hospital_los_days,
  AVG(mortality) * 100 AS mortality_rate_percent
FROM (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.proc_count_72h,
    a.hospital_los_days,
    a.mortality,
    NTILE(4) OVER (ORDER BY p.proc_count_72h) AS quartile
  FROM proc_72h AS p
  JOIN admit_stats AS a
    ON p.subject_id = a.subject_id
   AND p.hadm_id = a.hadm_id
) AS q
GROUP BY quartile
ORDER BY quartile;