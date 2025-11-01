WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND (d_icd.long_title LIKE '%hepatic failure%' OR d_icd.long_title LIKE '%liver failure%')
    )
),
medication_count AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT p.drug) AS med_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
    AND p.starttime >= c.admittime
    AND p.starttime <= c.admittime + INTERVAL 7 DAY
  GROUP BY c.hadm_id
),
cohort_with_med AS (
  SELECT
    c.*,
    COALESCE(m.med_count, 0) AS med_count,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE
        a2.subject_id = c.subject_id
        AND a2.hadm_id != c.hadm_id
        AND a2.admittime >= c.dischtime
        AND a2.admittime <= c.dischtime + INTERVAL 30 DAY
    ) THEN 1 ELSE 0 END AS readmission_flag
  FROM cohort c
  LEFT JOIN medication_count m ON c.hadm_id = m.hadm_id
),
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_count) AS tertile
  FROM cohort_with_med
)
SELECT
  tertile,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(readmission_flag) AS readmission_rate
FROM tertiles
GROUP BY tertile
ORDER BY tertile;