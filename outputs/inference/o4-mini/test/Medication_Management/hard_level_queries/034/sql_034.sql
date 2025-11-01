WITH surgical_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      ON a.hadm_id = pr.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.dischtime IS NOT NULL
),
med_complexity AS (
  SELECT
    sa.hadm_id,
    COUNT(DISTINCT rx.drug) AS unique_drugs,
    SUM(IF(rx.drug_type = 'High Risk', 2, 0)) AS highrisk_weight,
    COUNT(DISTINCT rx.drug) + SUM(IF(rx.drug_type = 'High Risk', 2, 0)) AS complexity_score
  FROM
    surgical_adm sa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
      ON sa.hadm_id = rx.hadm_id
      AND rx.starttime BETWEEN sa.admittime
                          AND TIMESTAMP_ADD(sa.admittime, INTERVAL 24 HOUR)
  GROUP BY
    sa.hadm_id
),
complexity_q AS (
  SELECT
    hadm_id,
    complexity_score,
    NTILE(4) OVER (ORDER BY complexity_score) AS quartile
  FROM
    med_complexity
),
readmissions_min AS (
  -- get the earliest subsequent admission time for each discharge
  SELECT
    sa.subject_id,
    sa.hadm_id,
    sa.dischtime,
    MIN(next_adm.admittime) AS next_adm_time
  FROM
    surgical_adm sa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next_adm
      ON sa.subject_id = next_adm.subject_id
      AND next_adm.admittime > sa.dischtime
  GROUP BY
    sa.subject_id,
    sa.hadm_id,
    sa.dischtime
),
readmissions AS (
  -- flag 30-day readmission
  SELECT
    subject_id,
    hadm_id,
    CASE 
      WHEN next_adm_time IS NOT NULL
       AND next_adm_time <= TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY)
      THEN 1
      ELSE 0
    END AS readmit_30d
  FROM
    readmissions_min
),
final AS (
  SELECT
    cq.quartile,
    AVG(TIMESTAMP_DIFF(sa.dischtime, sa.admittime, HOUR)/24.0) AS avg_los_days,
    AVG(sa.hospital_expire_flag) AS in_hosp_mortality_rate,
    AVG(r.readmit_30d) AS readmit_30d_rate,
    COUNT(*) AS admission_count
  FROM
    surgical_adm sa
    JOIN complexity_q cq
      ON sa.hadm_id = cq.hadm_id
    LEFT JOIN readmissions r
      ON sa.hadm_id = r.hadm_id
  GROUP BY
    cq.quartile
)
SELECT
  quartile,
  admission_count,
  ROUND(avg_los_days, 2) AS avg_los_days,
  ROUND(in_hosp_mortality_rate * 100, 2) AS in_hosp_mortality_pct,
  ROUND(readmit_30d_rate * 100, 2) AS readmit_30d_pct
FROM
  final
ORDER BY
  quartile;