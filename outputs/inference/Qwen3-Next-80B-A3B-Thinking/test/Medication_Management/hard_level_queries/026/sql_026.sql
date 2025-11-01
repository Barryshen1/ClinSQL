WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND ((EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age) BETWEEN 76 AND 86
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND di.long_title LIKE '%pneumonia%'
    )
),

medication_complexity AS (
  SELECT
    fa.hadm_id,
    COUNT(DISTINCT p.drug) AS drug_count
  FROM filtered_admissions fa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON fa.hadm_id = p.hadm_id
    AND p.starttime >= fa.admittime
    AND p.starttime <= fa.admittime + INTERVAL '7' DAY
  GROUP BY fa.hadm_id
),

readmission_flag AS (
  SELECT
    fa.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = fa.subject_id
        AND a2.admittime > fa.dischtime
        AND a2.admittime <= fa.dischtime + INTERVAL '30' DAY
    ) THEN 1 ELSE 0 END AS readmission_30d
  FROM filtered_admissions fa
),

combined AS (
  SELECT
    fa.hadm_id,
    mc.drug_count,
    DATE_DIFF(fa.dischtime, fa.admittime, DAY) AS los,
    fa.hospital_expire_flag,
    rf.readmission_30d
  FROM filtered_admissions fa
  LEFT JOIN medication_complexity mc ON fa.hadm_id = mc.hadm_id
  LEFT JOIN readmission_flag rf ON fa.hadm_id = rf.hadm_id
),

tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY drug_count) AS tertile
  FROM combined
)

SELECT
  tertile,
  COUNT(*) AS count,
  MIN(drug_count) AS min_score,
  AVG(drug_count) AS avg_score,
  MAX(drug_count) AS max_score,
  AVG(los) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct,
  AVG(readmission_30d) * 100 AS readmission_30d_pct
FROM tertiles
GROUP BY tertile
ORDER BY tertile;