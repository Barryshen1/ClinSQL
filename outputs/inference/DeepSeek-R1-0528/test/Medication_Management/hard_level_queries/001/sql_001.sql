WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pt.anchor_age,
    pt.anchor_year,
    pt.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt 
      ON adm.subject_id = pt.subject_id
  WHERE
    pt.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE
        diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code = '427.5')
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I46%')
        )
    )
),
cohort_filtered AS (
  SELECT
    *,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_adm
  FROM
    cohort
  WHERE
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 76 AND 86
),
med_score AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT em.medication) AS med_complexity_score
  FROM
    cohort_filtered c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` em 
      ON c.hadm_id = em.hadm_id
      AND em.charttime BETWEEN c.admittime 
        AND DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
      AND em.event_txt = 'Given'
  GROUP BY
    c.subject_id, c.hadm_id
),
cohort_with_med AS (
  SELECT
    c.*,
    COALESCE(m.med_complexity_score, 0) AS med_complexity_score
  FROM
    cohort_filtered c
    LEFT JOIN med_score m 
      ON c.hadm_id = m.hadm_id AND c.subject_id = m.subject_id
),
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY med_complexity_score) AS quintile
  FROM
    cohort_with_med
),
readmission_flag AS (
  SELECT
    q.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM
          `physionet-data.mimiciv_3_1_hosp.admissions` adm2
        WHERE
          adm2.subject_id = q.subject_id
          AND adm2.hadm_id <> q.hadm_id
          AND adm2.admittime > q.dischtime
          AND adm2.admittime <= DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmission_30d
  FROM
    quintiles q
)
SELECT
  quintile,
  COUNT(*) AS patient_count,
  AVG(med_complexity_score) AS avg_score,
  MIN(med_complexity_score) AS min_score,
  MAX(med_complexity_score) AS max_score,
  AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
  AVG(readmission_30d) * 100 AS readmission_30d_percent
FROM
  readmission_flag
GROUP BY
  quintile
ORDER BY
  quintile;