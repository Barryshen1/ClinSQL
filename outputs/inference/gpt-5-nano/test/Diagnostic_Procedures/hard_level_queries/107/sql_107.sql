WITH pe_subjects AS (
  -- Female patients aged 65-75 with pulmonary embolism in their hospitalization
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON di.subject_id = p.subject_id
  WHERE LOWER(dd.long_title) LIKE '%pulmonary embolism%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
),
first_stay AS (
  -- First ICU stay per subject from the PE-subjects pool
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  WHERE s.subject_id IN (SELECT subject_id FROM pe_subjects)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY s.subject_id ORDER BY s.intime) = 1
),
per_stay_metrics AS (
  -- For each first ICU stay, compute the diagnostic/procedure count within 72 hours
  SELECT
    fs.subject_id,
    fs.hadm_id,
    fs.stay_id,
    fs.intime,
    fs.outtime,
    fs.los,
    a.hospital_expire_flag,
    SUM(
      CASE
        WHEN pi.chartdate IS NOT NULL
             AND DATE(pi.chartdate) BETWEEN DATE(fs.intime) AND DATE_ADD(DATE(fs.intime), INTERVAL 3 DAY)
             AND (
                   LOWER(dp.long_title) LIKE '%diagnostic%'
                   OR LOWER(dp.long_title) LIKE '%imaging%'
                   OR LOWER(dp.long_title) LIKE '%diagnosis%'
                 )
        THEN 1
        ELSE 0
      END
    ) AS proc_count
  FROM first_stay fs
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON fs.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON pi.subject_id = fs.subject_id
   AND pi.hadm_id = fs.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pi.icd_code = dp.icd_code
   AND pi.icd_version = dp.icd_version
  GROUP BY
    fs.subject_id, fs.hadm_id, fs.stay_id, fs.intime, fs.outtime, fs.los, a.hospital_expire_flag
),
quartile_ready AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los,
    hospital_expire_flag,
    proc_count,
    NTILE(4) OVER (ORDER BY proc_count) AS quartile
  FROM per_stay_metrics
)
SELECT
  quartile,
  COUNT(*) AS N,
  AVG(proc_count) AS mean_proc_count,
  AVG(los) AS mean_icu_los_days,
  100 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_percent
FROM quartile_ready
GROUP BY quartile
ORDER BY quartile;