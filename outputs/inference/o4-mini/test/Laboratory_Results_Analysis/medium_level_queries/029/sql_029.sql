WITH troponin_t_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_troponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum AS troponin_value
  FROM (
    SELECT
      subject_id,
      hadm_id,
      charttime,
      valuenum,
      ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN troponin_t_itemids ti
      ON le.itemid = ti.itemid
    WHERE le.valuenum IS NOT NULL
  ) le
  WHERE rn = 1
),
ami_cp_admissions AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%myocardial infarction%'
     OR LOWER(dd.long_title) LIKE '%chest pain%'
),
eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND EXISTS (
      SELECT 1
      FROM ami_cp_admissions aca
      WHERE aca.hadm_id = a.hadm_id
    )
)
SELECT
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN ea.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  ROUND(
    SAFE_DIVIDE(
      SUM(CASE WHEN ea.hospital_expire_flag = 1 THEN 1 ELSE 0 END),
      COUNT(*)
    ) * 100,
    2
  ) AS mortality_rate_percent
FROM eligible_admissions ea
JOIN first_troponin ft
  ON ea.hadm_id = ft.hadm_id
WHERE ft.troponin_value > 0.04;