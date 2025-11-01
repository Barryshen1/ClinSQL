WITH ranked_index AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id
   AND a.hadm_id = di.hadm_id
   AND di.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE
    (LOWER(a.admission_type) LIKE '%transfer%' OR LOWER(a.admission_location) LIKE '%transfer%')
    AND LOWER(a.insurance) LIKE '%medicare%'
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
    AND LOWER(dd.long_title) LIKE '%heart failure%'
    -- Age at admission: approximate using birth year from anchor_year/anchor_age
    AND DATE_DIFF(
          DATE(a.admittime),
          DATE(p.anchor_year - p.anchor_age, 1, 1),
          YEAR
        ) BETWEEN 65 AND 75
)

SELECT
  COUNT(*) AS index_admission_count
FROM
  ranked_index
WHERE
  rn = 1;