WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND TIMESTAMP_DIFF(
          a.admittime,
          DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE),
          INTERVAL p.anchor_age YEAR),
          YEAR
        ) BETWEEN 70 AND 80
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE
        d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%hemorrhagic stroke%'
    )
),
cohort_lab_48h AS (
  SELECT
    c.hadm_id,
    COUNT(l.labevent_id) AS critical_lab_count_48h
  FROM cohort_admissions c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.subject_id = l.subject_id
    AND c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.flag IN ('critical', 'critical/high', 'critical/low')
  GROUP BY c.hadm_id
),
cohort_stats AS (
  SELECT
    (SELECT APPROX_QUANTILES(critical_lab_count_48h, 100)[OFFSET(25)] 
     FROM cohort_lab_48h) AS p25_critical_lab_count_48h,
    AVG(COALESCE(l_entire.critical_lab_count_entire, 0)) AS cohort_critical_lab_rate,
    AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY)) AS mean_los,
    AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM cohort_admissions c
  LEFT JOIN (
    SELECT
      subject_id,
      hadm_id,
      COUNT(*) AS critical_lab_count_entire
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE flag IN ('critical', 'critical/high', 'critical/low')
    GROUP BY subject_id, hadm_id
  ) l_entire
    ON c.subject_id = l_entire.subject_id
    AND c.hadm_id = l_entire.hadm_id
),
general_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE NOT EXISTS (
    SELECT 1
    FROM cohort_admissions c
    WHERE c.subject_id = a.subject_id
      AND c.hadm_id = a.hadm_id
  )
),
general_lab_events AS (
  SELECT
    g.hadm_id,
    COUNT(*) AS critical_lab_count_entire
  FROM general_admissions g
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON g.subject_id = l.subject_id
    AND g.hadm_id = l.hadm_id
    AND l.flag IN ('critical', 'critical/high', 'critical/low')
  GROUP BY g.hadm_id
),
general_stats AS (
  SELECT
    AVG(COALESCE(l.critical_lab_count_entire, 0)) AS general_critical_lab_rate
  FROM general_lab_events l
)
SELECT
  cs.*,
  gs.general_critical_lab_rate
FROM cohort_stats cs,
general_stats gs;