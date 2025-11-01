WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND LOWER(dd.long_title) LIKE '%stroke%'
    AND LOWER(dd.long_title) LIKE '%ischemic%'
),
cohort_lab_counts AS (
  SELECT
    c.hadm_id,
    COUNTIF(
      (l.valuenum IS NOT NULL AND l.ref_range_lower IS NOT NULL AND l.ref_range_upper IS NOT NULL
       AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper))
      OR LOWER(l.flag) LIKE '%abnormal%'
      OR LOWER(l.flag) LIKE '%critical%'
    ) AS abnormal_lab_count_72h
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
),
general_lab_counts AS (
  SELECT
    a.hadm_id,
    COUNTIF(
      (l.valuenum IS NOT NULL AND l.ref_range_lower IS NOT NULL AND l.ref_range_upper IS NOT NULL
       AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper))
      OR LOWER(l.flag) LIKE '%abnormal%'
      OR LOWER(l.flag) LIKE '%critical%'
    ) AS abnormal_lab_count_72h
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY a.hadm_id
),
cohort_stats AS (
  SELECT
    MIN(cl.abnormal_lab_count_72h) AS min_instability_score,
    AVG(cl.abnormal_lab_count_72h) AS avg_instability_score,
    AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY)) AS avg_los_days,
    AVG(c.hospital_expire_flag) AS in_hosp_mortality_rate
  FROM cohort c
  JOIN cohort_lab_counts cl
    ON c.hadm_id = cl.hadm_id
),
general_stats AS (
  SELECT
    AVG(abnormal_lab_count_72h) AS avg_instability_score_general
  FROM general_lab_counts
)
SELECT
  cs.min_instability_score,
  cs.avg_instability_score,
  gs.avg_instability_score_general,
  cs.avg_los_days,
  cs.in_hosp_mortality_rate
FROM cohort_stats cs
CROSS JOIN general_stats gs;