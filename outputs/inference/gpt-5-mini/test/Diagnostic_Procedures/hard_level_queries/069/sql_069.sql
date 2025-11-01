WITH pe_admissions AS (
  -- Admissions of male patients age 44-54 with a pulmonary embolism diagnosis
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id AND a.subject_id = di.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND LOWER(dd.long_title) LIKE '%pulmonary embol%'
),

first_icustays AS (
  -- First ICU stay (earliest intime) per hospital admission
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE hadm_id IN (SELECT hadm_id FROM pe_admissions)
  ) icu
  WHERE rn = 1
),

proc_counts AS (
  -- Count distinct procedures (by itemid) in the first 72 ICU hours for each first ICU stay
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    COALESCE(COUNT(DISTINCT p.itemid), 0) AS proc_count
  FROM first_icustays f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON p.subject_id = f.subject_id
   AND p.hadm_id = f.hadm_id
   AND p.stay_id = f.stay_id
   AND p.starttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY f.subject_id, f.hadm_id, f.stay_id, f.intime
),

proc_quintiles AS (
  -- Assign quintiles based on procedure count (lowest counts -> quintile 1)
  SELECT
    pc.*,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM proc_counts pc
),

final_prep AS (
  -- Attach admission-level outcomes (LOS and hospital mortality)
  SELECT
    q.quintile,
    q.proc_count,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- LOS in days with fractional days
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR), 24.0) AS los_days
  FROM proc_quintiles q
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON q.hadm_id = a.hadm_id
  -- Ensure we only consider admissions in the PE cohort (redundant but explicit)
  WHERE a.hadm_id IN (SELECT hadm_id FROM pe_admissions)
)

SELECT
  quintile,
  COUNT(*) AS n_stays,
  ROUND(AVG(proc_count), 2) AS avg_proc_count,
  ROUND(AVG(los_days), 2) AS avg_hospital_los_days,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent
FROM final_prep
GROUP BY quintile
ORDER BY quintile;