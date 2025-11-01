WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND (
      d.icd_code = 'K92.2'
      OR LOWER(d_icd.long_title) LIKE '%lower%gastrointestinal%hemorrhage%'
      OR LOWER(d_icd.long_title) LIKE '%lower%gi%bleed%'
    )
),

lab_instability AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(*) AS lab_instability_score
  FROM cohort c
  JOIN physionet-data.mimiciv_3_1_hosp.labevents l
    ON c.subject_id = l.subject_id
  WHERE l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.flag = 'abnormal'
  GROUP BY c.subject_id, c.hadm_id
),

quintiles AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    l.lab_instability_score,
    NTILE(5) OVER (ORDER BY l.lab_instability_score) AS quintile
  FROM cohort c
  JOIN lab_instability l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
),

general_rate AS (
  SELECT
    AVG(abnormal_count) AS avg_abnormal_labs_general
  FROM (
    SELECT
      COUNT(*) AS abnormal_count
    FROM physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN physionet-data.mimiciv_3_1_hosp.labevents l
      ON a.subject_id = l.subject_id
    WHERE l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
      AND l.flag = 'abnormal'
    GROUP BY a.hadm_id
  )
)

SELECT
  q.quintile,
  AVG(TIMESTAMP_DIFF(q.dischtime, q.admittime, HOUR) / 24.0) AS avg_los_days,
  AVG(CAST(q.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
  AVG(q.lab_instability_score) AS avg_lab_instability_score,
  gr.avg_abnormal_labs_general
FROM quintiles q
CROSS JOIN general_rate gr
GROUP BY q.quintile, gr.avg_abnormal_labs_general
ORDER BY q.quintile;