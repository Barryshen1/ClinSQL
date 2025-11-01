WITH cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los AS icu_los,
    CASE
      WHEN d.icd_code IN ('430', '431', '432', 'I61', 'I62') THEN 'Hemorrhagic Stroke'
      ELSE 'Other'
    END AS stroke_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

procedures_first_72hr AS (
  SELECT
    c.stay_id,
    c.stroke_group,
    c.icu_los,
    c.hospital_expire_flag,
    COUNT(proc.icd_code) AS proc_count
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON c.hadm_id = proc.hadm_id
  WHERE
    proc.chartdate >= c.intime
    AND proc.chartdate <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY
    c.stay_id, c.stroke_group, c.icu_los, c.hospital_expire_flag
),

grouped_stats AS (
  SELECT
    stroke_group,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(90)] AS proc_count_90th_percentile,
    AVG(icu_los) AS mean_icu_los,
    AVG(hospital_expire_flag) AS in_hospital_mortality_rate
  FROM
    procedures_first_72hr
  GROUP BY
    stroke_group
)

SELECT
  stroke_group,
  proc_count_90th_percentile,
  mean_icu_los,
  in_hospital_mortality_rate
FROM
  grouped_stats
ORDER BY
  stroke_group;