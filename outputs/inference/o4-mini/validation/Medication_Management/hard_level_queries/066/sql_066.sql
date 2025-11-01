WITH first_txn_adm AS (
  -- Identify the first transplant admission per male patient age 43–53
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND LOWER(dd.long_title) LIKE '%transplant%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
),
index_adm AS (
  -- Keep only the first transplant admission per patient
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    los
  FROM first_txn_adm
  WHERE rn = 1
),
med_complexity AS (
  -- Compute medication complexity score = distinct drugs in first 7 days
  SELECT
    ia.subject_id,
    ia.hadm_id,
    COUNT(DISTINCT rx.drug) AS score
  FROM index_adm ia
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON ia.subject_id = rx.subject_id
    AND ia.hadm_id = rx.hadm_id
    AND rx.starttime >= ia.admittime
    AND rx.starttime < ia.admittime + INTERVAL 7 DAY
  GROUP BY
    ia.subject_id,
    ia.hadm_id
),
readmit30 AS (
  -- Flag 30-day readmission
  SELECT
    ia.subject_id,
    ia.hadm_id,
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END AS readmit30_flag
  FROM index_adm ia
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` later
    ON ia.subject_id = later.subject_id
    AND later.admittime > ia.dischtime
    AND later.admittime <= ia.dischtime + INTERVAL 30 DAY
  GROUP BY
    ia.subject_id,
    ia.hadm_id
),
scored AS (
  -- Combine scores and outcomes and assign quartiles
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.score,
    ia.los,
    ia.hospital_expire_flag,
    r.readmit30_flag,
    NTILE(4) OVER (ORDER BY mc.score) AS quartile
  FROM med_complexity mc
  JOIN index_adm ia
    ON mc.subject_id = ia.subject_id
    AND mc.hadm_id = ia.hadm_id
  JOIN readmit30 r
    ON mc.subject_id = r.subject_id
    AND mc.hadm_id = r.hadm_id
)
-- Final aggregation by quartile
SELECT
  quartile,
  COUNT(*) AS n,
  ROUND(AVG(score),2) AS mean_score,
  ROUND(AVG(los),2) AS mean_los,
  ROUND(AVG(hospital_expire_flag),3) AS mortality_rate,
  ROUND(AVG(readmit30_flag),3) AS readmit30_rate
FROM scored
GROUP BY quartile
ORDER BY quartile;