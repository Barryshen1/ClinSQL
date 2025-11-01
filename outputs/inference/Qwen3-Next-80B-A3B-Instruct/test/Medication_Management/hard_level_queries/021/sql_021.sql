WITH qualifying_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND EXISTS (
      -- Neutropenia within first 48h
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
      JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
      WHERE le.subject_id = a.subject_id
        AND le.hadm_id = a.hadm_id
        AND le.charttime BETWEEN a.admittime AND a.admittime + INTERVAL 48 HOUR
        AND dl.label = 'Neutrophils'
        AND le.valuenum < 1500
    )
    AND EXISTS (
      -- Fever within first 48h
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
      WHERE ce.subject_id = a.subject_id
        AND ce.hadm_id = a.hadm_id
        AND ce.charttime BETWEEN a.admittime AND a.admittime + INTERVAL 48 HOUR
        AND di.label = 'Temperature'
        AND ce.valuenum >= 38.0
    )
),
medication_counts AS (
  SELECT
    qp.subject_id,
    qp.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_med_count
  FROM qualifying_patients qp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON qp.hadm_id = p.hadm_id
    AND p.starttime BETWEEN qp.admittime AND qp.admittime + INTERVAL 48 HOUR
  GROUP BY qp.subject_id, qp.hadm_id
),
tertiles AS (
  SELECT
    mc.*,
    NTILE(3) OVER (ORDER BY mc.unique_med_count) AS medication_tertile
  FROM medication_counts mc
),
readmissions AS (
  SELECT
    a1.subject_id,
    a1.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = a1.subject_id
          AND a2.hadm_id != a1.hadm_id
          AND a2.admittime >= a1.dischtime
          AND a2.admittime <= a1.dischtime + INTERVAL 30 DAY
      ) THEN 1
      ELSE 0
    END AS thirty_day_readmission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
),
final_analysis AS (
  SELECT
    t.medication_tertile,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60)) AS los_days,
    AVG(CAST(a.hospital_expire_flag AS FLOAT)) * 100 AS in_hospital_mortality_pct,
    AVG(CAST(r.thirty_day_readmission AS FLOAT)) * 100 AS thirty_day_readmission_pct
  FROM tertiles t
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON t.hadm_id = a.hadm_id
  LEFT JOIN readmissions r ON t.hadm_id = r.hadm_id
  GROUP BY t.medication_tertile
  ORDER BY t.medication_tertile
)
SELECT
  medication_tertile,
  ROUND(los_days, 2) AS los_days,
  ROUND(in_hospital_mortality_pct, 2) AS in_hospital_mortality_pct,
  ROUND(thirty_day_readmission_pct, 2) AS thirty_day_readmission_pct
FROM final_analysis;