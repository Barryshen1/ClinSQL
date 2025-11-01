WITH first_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
),
demo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
),
-- identify sepsis admissions
sepsis_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE LOWER(di.long_title) LIKE '%sepsis%'
),
-- base cohort: female, age 66-76, first ICU stay
cohort AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    demo.gender,
    demo.anchor_age,
    CASE WHEN s.subject_id IS NOT NULL THEN 1 ELSE 0 END AS sepsis_flag
  FROM first_icu f
  JOIN demo
    ON f.subject_id = demo.subject_id
  LEFT JOIN sepsis_admissions s
    ON f.subject_id = s.subject_id AND f.hadm_id = s.hadm_id
  WHERE f.rn = 1
    AND demo.gender = 'F'
    AND demo.anchor_age BETWEEN 66 AND 76
),
-- count distinct procedures in first 48 hours
proc_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.sepsis_flag,
    COUNT(DISTINCT pproc.icd_code) AS proc_count_48h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pproc
    ON c.subject_id = pproc.subject_id AND c.hadm_id = pproc.hadm_id
    AND DATE(pproc.chartdate) BETWEEN DATE(c.intime) AND DATE(c.intime + INTERVAL 2 DAY)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.sepsis_flag
),
-- hospital LOS and mortality
hospital_stats AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.sepsis_flag,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.subject_id = a.subject_id AND c.hadm_id = a.hadm_id
)
-- final outputs
SELECT
  'cases' AS group_type,
  APPROX_QUANTILES(proc_count_48h, 100)[OFFSET(90)] AS proc_count_90th,
  AVG(hosp_los) AS avg_hosp_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM proc_counts pc
JOIN hospital_stats hs
  ON pc.subject_id = hs.subject_id AND pc.hadm_id = hs.hadm_id
WHERE pc.sepsis_flag = 1

UNION ALL

SELECT
  'controls' AS group_type,
  NULL AS proc_count_90th, -- not required for controls
  AVG(hosp_los) AS avg_hosp_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM proc_counts pc
JOIN hospital_stats hs
  ON pc.subject_id = hs.subject_id AND pc.hadm_id = hs.hadm_id
WHERE pc.sepsis_flag = 0
;