WITH first_icustay_per_subject AS (
  -- select each subject's first ICU stay (earliest intime)
  SELECT
    icustays.*
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
  ) icustays
  WHERE rn = 1
),

cohort AS (
  -- cohort: male patients aged 37-47 on their first ICU stay
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los
  FROM
    first_icustay_per_subject f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON f.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),

proc_counts AS (
  -- count distinct procedures (by itemid) occurring within first 48 hours of ICU intime
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COALESCE(count_distinct_itemid, 0) AS proc_count
  FROM
    cohort c
  LEFT JOIN (
    SELECT
      pe.stay_id,
      COUNT(DISTINCT pe.itemid) AS count_distinct_itemid
    FROM
      `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN
      -- join to cohort stays to apply the 48-hour window cleanly
      (SELECT stay_id, intime FROM first_icustay_per_subject) fi
      ON pe.stay_id = fi.stay_id
    WHERE
      pe.starttime IS NOT NULL
      AND pe.starttime BETWEEN fi.intime AND TIMESTAMP_ADD(fi.intime, INTERVAL 48 HOUR)
    GROUP BY
      pe.stay_id
  ) pc
  ON c.stay_id = pc.stay_id
),

cohort_with_counts AS (
  -- attach LOS and hospital mortality
  SELECT
    cc.subject_id,
    cc.hadm_id,
    cc.stay_id,
    cc.proc_count,
    co.los,
    adm.hospital_expire_flag
  FROM
    proc_counts cc
  JOIN
    cohort co
    ON cc.stay_id = co.stay_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON cc.hadm_id = adm.hadm_id
),

quintiled AS (
  -- assign quintiles by proc_count (ascending). tie-breaker subject_id for determinism.
  SELECT
    *,
    NTILE(5) OVER (ORDER BY proc_count, subject_id) AS proc_count_quintile
  FROM
    cohort_with_counts
)

SELECT
  proc_count_quintile AS quintile,
  COUNT(*) AS n_patients,
  ROUND(AVG(proc_count), 3) AS mean_proc_count,
  ROUND(AVG(los), 3) AS mean_icu_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 4) AS hospital_mortality_rate
FROM
  quintiled
GROUP BY
  proc_count_quintile
ORDER BY
  proc_count_quintile;