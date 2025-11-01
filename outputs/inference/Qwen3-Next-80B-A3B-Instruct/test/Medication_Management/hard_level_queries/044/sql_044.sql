WITH pe_patients AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    AND LOWER(d_icd.long_title) LIKE '%pulmonary embolism%'
),

meds_first_24h AS (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT rx.drug) AS med_count
  FROM pe_patients p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON p.hadm_id = rx.hadm_id
    AND rx.starttime >= p.admittime
    AND rx.starttime <= p.admittime + INTERVAL '24' HOUR
  GROUP BY p.hadm_id
),

med_tertiles AS (
  SELECT
    p.*,
    COALESCE(m.med_count, 0) AS med_count,
    NTILE(3) OVER (ORDER BY COALESCE(m.med_count, 0)) AS med_tertile
  FROM pe_patients p
  LEFT JOIN meds_first_24h m ON p.hadm_id = m.hadm_id
),

readmissions AS (
  SELECT
    a1.hadm_id,
    CASE
      WHEN a2.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmit_30d
  FROM pe_patients a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= a1.dischtime + INTERVAL '30' DAY
),

final_agg AS (
  SELECT
    mt.med_tertile,
    COUNT(*) AS admissions,
    MIN(mt.med_count) AS med_score_min,
    MAX(mt.med_count) AS med_score_max,
    AVG(TIMESTAMP_DIFF(mt.dischtime, mt.admittime, HOUR) / 24.0) AS los_days,
    AVG(CAST(mt.hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct,
    AVG(CAST(r.readmit_30d AS FLOAT64)) * 100 AS readmit_30d_pct
  FROM med_tertiles mt
  JOIN readmissions r ON mt.hadm_id = r.hadm_id
  GROUP BY mt.med_tertile
  ORDER BY mt.med_tertile
)

SELECT
  med_tertile,
  admissions,
  med_score_min,
  med_score_max,
  ROUND(los_days, 2) AS los_days,
  ROUND(mortality_pct, 2) AS mortality_pct,
  ROUND(readmit_30d_pct, 2) AS readmit_30d_pct
FROM final_agg;