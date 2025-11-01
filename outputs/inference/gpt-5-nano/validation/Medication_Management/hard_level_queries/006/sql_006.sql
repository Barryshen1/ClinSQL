WITH cohort_admissions AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = i.subject_id
  WHERE UPPER(p.gender) = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      WHERE pr.subject_id = a.subject_id AND pr.hadm_id = a.hadm_id
    )
),
meds AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ca.stay_id,
    COUNT(DISTINCT ie.itemid) AS med_complexity
  FROM cohort_admissions AS ca
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
    ON ie.subject_id = ca.subject_id
   AND ie.hadm_id = ca.hadm_id
   AND ie.stay_id = ca.stay_id
   AND ie.starttime >= ca.intime
   AND ie.starttime < TIMESTAMP_ADD(ca.intime, INTERVAL 72 HOUR)
  GROUP BY ca.subject_id, ca.hadm_id, ca.stay_id
)
SELECT
  quintile,
  AVG(los_days) AS avg_los_days,
  AVG(mortality) AS mortality_rate,
  AVG(readmit_30d) AS readmit_rate,
  COUNT(*) AS n_patients
FROM (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    m.med_complexity,
    NTILE(5) OVER (ORDER BY m.med_complexity) AS quintile,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1
      ELSE 0
    END AS mortality,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = a.subject_id
          AND a2.hadm_id <> a.hadm_id
          AND a2.admittime >= a.dischtime
          AND a2.admittime < TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_30d
  FROM meds AS m
  JOIN cohort_admissions AS ca
    ON ca.subject_id = m.subject_id
   AND ca.hadm_id = m.hadm_id
   AND ca.stay_id = m.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.subject_id = m.subject_id
   AND a.hadm_id = m.hadm_id
) AS t
GROUP BY quintile
ORDER BY quintile;