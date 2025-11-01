WITH lower_gi_hadms AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%lower gastrointestinal%' 
    AND LOWER(dd.long_title) LIKE '%hemorrhage%'
),
first_icu_stays AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    los
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) = 1
),
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    s.stay_id,
    s.intime,
    s.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN first_icu_stays s
    ON p.subject_id = s.subject_id
   AND a.hadm_id = s.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND a.hadm_id IN (SELECT hadm_id FROM lower_gi_hadms)
),
proc_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.los,
    c.hospital_expire_flag,
    COUNT(DISTINCT pr.icd_code) AS proc_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON c.subject_id = pr.subject_id
   AND c.hadm_id = pr.hadm_id
   AND pr.chartdate >= DATE(c.intime)
   AND pr.chartdate < DATE_ADD(DATE(c.intime), INTERVAL 2 DAY)
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.los,
    c.hospital_expire_flag
),
with_quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM proc_counts
)
SELECT
  quintile,
  ROUND(AVG(proc_count), 2)        AS mean_proc_count,
  ROUND(AVG(los), 2)               AS mean_icu_los_days,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2)
                                    AS in_hospital_mortality_pct
FROM with_quintiles
GROUP BY quintile
ORDER BY quintile;