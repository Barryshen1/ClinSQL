WITH base AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
    )
)
SELECT
  hospital_expire_flag AS survival_status,
  AVG(hospital_los) AS mean_los,
  STDDEV(hospital_los) AS sd_los,
  AVG(CASE WHEN hospital_los < 7 THEN 1.0 ELSE 0 END) * 100 AS percent_los_lt7
FROM base
WHERE age BETWEEN 35 AND 45
GROUP BY survival_status
ORDER BY survival_status;