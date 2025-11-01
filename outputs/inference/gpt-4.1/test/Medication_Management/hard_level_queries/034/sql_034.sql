WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.services` s
    ON a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND (
      a.admission_type LIKE '%SURGICAL%'
      OR s.curr_service LIKE '%SURG%'
    )
),

meds AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT LOWER(pr.drug)) AS unique_drugs,
    COUNT(DISTINCT CASE
      WHEN LOWER(pr.drug) LIKE '%warfarin%' OR
           LOWER(pr.drug) LIKE '%heparin%' OR
           LOWER(pr.drug) LIKE '%insulin%' OR
           LOWER(pr.drug) LIKE '%morphine%' OR
           LOWER(pr.drug) LIKE '%fentanyl%' OR
           LOWER(pr.drug) LIKE '%hydromorphone%' OR
           LOWER(pr.drug) LIKE '%oxycodone%' OR
           LOWER(pr.drug) LIKE '%methadone%' OR
           LOWER(pr.drug) LIKE '%digoxin%' OR
           LOWER(pr.drug) LIKE '%vancomycin%' OR
           LOWER(pr.drug) LIKE '%gentamicin%' OR
           LOWER(pr.drug) LIKE '%amikacin%' OR
           LOWER(pr.drug) LIKE '%phenytoin%' OR
           LOWER(pr.drug) LIKE '%carbamazepine%' OR
           LOWER(pr.drug) LIKE '%valproate%' OR
           LOWER(pr.drug) LIKE '%clozapine%' OR
           LOWER(pr.drug) LIKE '%lithium%'
        THEN LOWER(pr.drug)
      ELSE NULL
    END) AS high_risk_drugs
  FROM
    cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id
    AND c.hadm_id = pr.hadm_id
    AND pr.starttime >= c.admittime
    AND pr.starttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY
    c.subject_id, c.hadm_id
),

complexity AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.unique_drugs,
    m.high_risk_drugs,
    (m.unique_drugs + 2 * m.high_risk_drugs) AS complexity_score
  FROM
    meds m
),

quartiles AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.unique_drugs,
    c.high_risk_drugs,
    c.complexity_score,
    co.admittime,
    co.dischtime,
    co.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY c.complexity_score) AS complexity_quartile
  FROM
    complexity c
  JOIN
    cohort co
    ON c.subject_id = co.subject_id AND c.hadm_id = co.hadm_id
),

readmissions AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    q.complexity_quartile,
    q.admittime,
    q.dischtime,
    q.hospital_expire_flag,
    TIMESTAMP_DIFF(q.dischtime, q.admittime, DAY) AS los,
    -- Find if there is a next admission within 30 days
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = q.subject_id
          AND a2.admittime > q.dischtime
          AND a2.admittime <= DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_30d
  FROM
    quartiles q
)

SELECT
  complexity_quartile,
  COUNT(*) AS admissions,
  ROUND(AVG(los), 2) AS avg_los_days,
  ROUND(100 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS in_hospital_mortality_pct,
  ROUND(100 * AVG(CAST(readmit_30d AS FLOAT64)), 2) AS readmission_30d_pct
FROM
  readmissions
GROUP BY
  complexity_quartile
ORDER BY
  complexity_quartile;