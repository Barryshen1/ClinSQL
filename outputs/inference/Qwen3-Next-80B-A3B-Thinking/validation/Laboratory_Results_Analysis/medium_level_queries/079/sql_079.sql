SELECT
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS p25,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) AS p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) AS p75,
  MIN(valuenum) AS min,
  MAX(valuenum) AS max
FROM (
  SELECT
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN (
    SELECT
      hadm_id,
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE itemid = 50911
  ) le ON a.hadm_id = le.hadm_id AND le.rn = 1
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 82 AND 92
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = '9' AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '786.5%'))
          OR
          (d.icd_version = '10' AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'R07%'))
        )
    )
    AND le.valuenum > 0.01
);