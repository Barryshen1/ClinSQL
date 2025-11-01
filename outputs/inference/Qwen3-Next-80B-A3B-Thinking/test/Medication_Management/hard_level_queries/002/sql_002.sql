WITH amipatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE
        d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'I21%'
    )
),
medication_scores AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT e.medication) AS med_count
  FROM amipatients a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON a.hadm_id = e.hadm_id
    AND e.charttime BETWEEN a.admittime AND a.admittime + INTERVAL '24' HOUR
  GROUP BY a.hadm_id
),
readmission AS (
  SELECT
    a.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE
        a2.subject_id = a.subject_id
        AND a2.admittime > a.dischtime
        AND a2.admittime <= a.dischtime + INTERVAL '30' DAY
    ) THEN 1 ELSE 0 END AS readmission_30d
  FROM amipatients a
),
combined AS (
  SELECT
    a.hadm_id,
    ms.med_count,
    a.los_days,
    a.hospital_expire_flag,
    r.readmission_30d,
    NTILE(3) OVER (ORDER BY ms.med_count) AS tertile
  FROM amipatients a
  JOIN medication_scores ms ON a.hadm_id = ms.hadm_id
  JOIN readmission r ON a.hadm_id = r.hadm_id
)
SELECT
  tertile,
  COUNT(*) AS admission_count,
  MIN(med_count) AS min_score,
  MAX(med_count) AS max_score,
  AVG(med_count) AS mean_score,
  AVG(los_days) AS mean_los_days,
  AVG(CAST(hospital_expire_flag AS INT64)) * 100 AS inhospital_mortality_pct,
  AVG(readmission_30d) * 100 AS readmission_30d_pct
FROM combined
GROUP BY tertile
ORDER BY tertile;