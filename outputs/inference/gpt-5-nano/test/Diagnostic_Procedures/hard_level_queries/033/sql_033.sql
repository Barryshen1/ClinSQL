WITH pneumonia_adm AS (
  -- Admissions (subject_id, hadm_id) with pneumonia diagnosis
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE LOWER(di.long_title) LIKE '%pneumonia%'
),
first_icu AS (
  -- First ICU stay per subject
  SELECT subject_id, hadm_id, stay_id, intime, outtime
  FROM (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      intime,
      outtime,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) t
  WHERE rn = 1
),
cohort AS (
  -- Cohort: first ICU stay, pneumonia admission, male, age 37-47 at admission
  SELECT fi.subject_id, fi.hadm_id, fi.stay_id, fi.intime, fi.outtime
  FROM first_icu fi
  JOIN pneumonia_adm pa
    ON pa.subject_id = fi.subject_id AND pa.hadm_id = fi.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = fi.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = fi.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age +
         (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 37 AND 47
),
proc_counts AS (
  -- Distinct procedures in first 48 hours and ICU LOS
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_count,
    TIMESTAMP_DIFF(c.outtime, c.intime, SECOND) / 86400.0 AS icu_los_days
  FROM cohort AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON pe.subject_id = c.subject_id
   AND pe.hadm_id = c.hadm_id
   AND pe.stay_id = c.stay_id
   AND pe.starttime >= c.intime
   AND pe.starttime < TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.intime, c.outtime
),
with_mortality AS (
  -- Attach mortality indicator from admissions
  SELECT pc.subject_id,
         pc.hadm_id,
         pc.stay_id,
         pc.proc_count,
         pc.icu_los_days,
         CASE WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS mortality
  FROM proc_counts pc
  JOIN cohort c
    ON c.subject_id = pc.subject_id
   AND c.hadm_id = pc.hadm_id
   AND c.stay_id = pc.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = pc.hadm_id
)
SELECT
  quintile,
  AVG(proc_count) AS mean_proc_count,
  AVG(icu_los_days) AS mean_icu_los_days,
  AVG(mortality) AS hospital_mortality_rate
FROM (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    proc_count,
    icu_los_days,
    mortality,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM with_mortality
) t
GROUP BY quintile
ORDER BY quintile;