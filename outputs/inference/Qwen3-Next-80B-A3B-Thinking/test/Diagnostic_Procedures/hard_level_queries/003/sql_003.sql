WITH procedure_counts AS (
  SELECT
    i.stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.stay_id = pe.stay_id
    AND pe.starttime >= i.intime
    AND pe.starttime <= i.intime + INTERVAL '24 hours'
  GROUP BY i.stay_id
),
admissions_info AS (
  SELECT
    i.stay_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = i.hadm_id
        AND d.icd_code = 'J80'
        AND d.icd_version = 10
    ) THEN 1 ELSE 0 END AS has_ards
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
)
SELECT
  CASE
    WHEN has_ards = 1 AND gender = 'F' AND anchor_age BETWEEN 84 AND 94 THEN 'ARDS'
    ELSE 'General'
  END AS group_label,
  PERCENTILE_CONT(proc_count, 0.25) WITHIN GROUP (ORDER BY proc_count) AS p25,
  PERCENTILE_CONT(proc_count, 0.75) WITHIN GROUP (ORDER BY proc_count) AS p75,
  PERCENTILE_CONT(proc_count, 0.95) WITHIN GROUP (ORDER BY proc_count) AS p95,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM admissions_info ai
JOIN procedure_counts pc ON ai.stay_id = pc.stay_id
GROUP BY group_label;