WITH cabg_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 74 AND 84
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
        ON pi.icd_code = d.icd_code AND pi.icd_version = d.icd_version
      WHERE pi.hadm_id = a.hadm_id
        AND (
          LOWER(d.long_title) LIKE '%coronary artery bypass%'
          OR LOWER(d.long_title) LIKE '%cabg%'
        )
    )
),
first_cabg AS (
  SELECT 
    subject_id,
    hadm_id,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM cabg_admissions
)
SELECT 
  AVG(icu.los) AS mean_icu_los_days
FROM first_cabg f
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON f.hadm_id = icu.hadm_id
WHERE f.rn = 1;