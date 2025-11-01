WITH hhs_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 50 AND 60
    AND di.long_title LIKE '%hyperosmolar%'
),
glucose_48h AS (
  SELECT
    h.hadm_id,
    STDDEV(l.valuenum) AS instability_score
  FROM
    hhs_patients h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON h.hadm_id = l.hadm_id
  WHERE
    l.itemid = 50809
    AND l.charttime BETWEEN h.admittime AND h.admittime + INTERVAL 48 HOUR
  GROUP BY
    h.hadm_id
),
percentile AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS threshold
  FROM
    glucose_48h
  WHERE
    instability_score IS NOT NULL
),
high_instability AS (
  SELECT
    h.hadm_id,
    h.hospital_expire_flag,
    h.admittime,
    h.dischtime
  FROM
    hhs_patients h
  JOIN
    glucose_48h g
    ON h.hadm_id = g.hadm_id
  CROSS JOIN
    percentile p
  WHERE
    g.instability_score >= p.threshold
),
critical_hhs AS (
  SELECT
    COUNTIF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
        WHERE l.hadm_id = hi.hadm_id
          AND l.itemid = 50809
          AND l.charttime BETWEEN hi.admittime AND hi.admittime + INTERVAL 48 HOUR
          AND (l.valuenum < 40 OR l.valuenum > 600)
      )
    ) AS critical_count,
    COUNT(*) AS total_count
  FROM
    high_instability hi
),
critical_general AS (
  SELECT
    COUNTIF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
        WHERE l.hadm_id = a.hadm_id
          AND l.itemid = 50809
          AND l.charttime BETWEEN a.admittime AND a.admittime + INTERVAL 48 HOUR
          AND (l.valuenum < 40 OR l.valuenum > 600)
      )
    ) AS critical_count,
    COUNT(*) AS total_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
)
SELECT
  AVG(hi.hospital_expire_flag) AS mortality_rate,
  AVG(DATE_DIFF(hi.dischtime, hi.admittime, DAY)) AS mean_los_days,
  (ch.critical_count / ch.total_count) AS hhs_critical_rate,
  (cg.critical_count / cg.total_count) AS general_critical_rate
FROM
  high_instability hi
CROSS JOIN
  critical_hhs ch
CROSS JOIN
  critical_general cg;