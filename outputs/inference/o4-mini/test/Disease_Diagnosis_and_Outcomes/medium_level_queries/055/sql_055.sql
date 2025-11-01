WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    -- LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- ICU flag
    CASE WHEN icu.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- filter age & sex
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    -- join complication-of-care diagnoses
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
    AND LOWER(dd.long_title) LIKE '%complication%'
    AND LOWER(dd.long_title) LIKE '%care%'
    -- left join to icustays to flag ICU admissions
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON a.subject_id = icu.subject_id
      AND a.hadm_id = icu.hadm_id
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    icu.stay_id
),
-- Compute quartiles over entire cohort
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM cohort
),
-- Flags for ventilation, vasopressors, RRT
hadm_flags AS (
  SELECT
    q.*,
    -- mech vent via procedure codes
    MAX(CASE WHEN LOWER(proc.long_title) LIKE '%ventilation%' THEN 1 ELSE 0 END) AS flag_vent,
    -- vasopressors via drug names
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%inephrine%' 
                  OR LOWER(pr.drug) LIKE '%dopamine%' 
                  OR LOWER(pr.drug) LIKE '%vasopress%' THEN 1 ELSE 0 END) AS flag_vaso,
    -- RRT via dialysis procedure codes
    MAX(CASE WHEN LOWER(proc.long_title) LIKE '%dialysis%' 
                  OR LOWER(proc.long_title) LIKE '%renal replacement%' THEN 1 ELSE 0 END) AS flag_rrt
  FROM
    quartiles q
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc_icd
      ON q.hadm_id = proc_icd.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` proc
      ON proc_icd.icd_code = proc.icd_code
      AND proc_icd.icd_version = proc.icd_version
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON q.hadm_id = pr.hadm_id
  GROUP BY
    q.subject_id,
    q.hadm_id,
    q.admittime,
    q.dischtime,
    q.hospital_expire_flag,
    q.anchor_age,
    q.gender,
    q.los_days,
    q.icu_flag,
    q.los_quartile
)
SELECT
  hf.icu_flag,
  hf.los_quartile,
  COUNT(*) AS n_admissions,
  SUM(hf.hospital_expire_flag) AS n_deaths,
  ROUND(100.0 * SUM(hf.hospital_expire_flag) / COUNT(*), 1) AS pct_mortality,
  -- Q1 mortality for absolute & relative comparisons
  ROUND(
    100.0 * SUM(hf.hospital_expire_flag) / COUNT(*) 
    - 100.0 * FIRST_VALUE(SUM(hf.hospital_expire_flag) / COUNT(*))
        OVER (PARTITION BY hf.icu_flag ORDER BY hf.los_quartile ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING),
    1
  ) AS abs_mortality_vs_Q1,
  ROUND(
    SAFE_DIVIDE(
      100.0 * SUM(hf.hospital_expire_flag) / COUNT(*),
      FIRST_VALUE(100.0 * SUM(hf.hospital_expire_flag) / COUNT(*))
        OVER (PARTITION BY hf.icu_flag ORDER BY hf.los_quartile ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
    ),
    2
  ) AS rel_mortality_vs_Q1,
  ROUND(100.0 * AVG(hf.flag_vent), 1) AS pct_mech_vent,
  ROUND(100.0 * AVG(hf.flag_vaso), 1) AS pct_vasopressors,
  ROUND(100.0 * AVG(hf.flag_rrt), 1) AS pct_rrt
FROM
  hadm_flags hf
GROUP BY
  hf.icu_flag,
  hf.los_quartile
ORDER BY
  hf.icu_flag,
  hf.los_quartile;