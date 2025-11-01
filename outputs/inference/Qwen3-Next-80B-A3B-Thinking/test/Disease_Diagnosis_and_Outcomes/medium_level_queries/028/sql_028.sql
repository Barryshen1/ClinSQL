WITH cohort AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    COUNTIF(d.icd_code NOT LIKE '428%' AND d.icd_code NOT LIKE 'I50%') AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.subject_id = a.subject_id
        AND d2.hadm_id = a.hadm_id
        AND (d2.icd_code LIKE '428%' OR d2.icd_code LIKE 'I50%')
    )
  GROUP BY a.hadm_id, a.hospital_expire_flag, los_days
),
stratified AS (
  SELECT
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile,
    NTILE(3) OVER (ORDER BY comorbidity_count) AS comorbidity_tertile,
    hospital_expire_flag
  FROM cohort
)
SELECT
  los_quartile,
  comorbidity_tertile,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate_percent
FROM stratified
GROUP BY los_quartile, comorbidity_tertile
ORDER BY los_quartile, comorbidity_tertile;