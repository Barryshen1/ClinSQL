WITH hf_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d.icd_code = dicd.icd_code
      AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 65
    AND LOWER(COALESCE(dicd.long_title, '')) LIKE '%heart failure%'
),

sodium_lab_items AS (
  SELECT DISTINCT d.itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  WHERE
    d.loinc_code = '2951-2'
    OR (LOWER(d.label) LIKE '%sodium%' AND LOWER(COALESCE(d.fluid, '')) LIKE '%serum%')
)

SELECT
  MIN(le.valuenum) AS min_admission_serum_sodium_mmol_per_l
FROM
  hf_admissions ha
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ha.hadm_id = le.hadm_id
  JOIN sodium_lab_items sli
    ON le.itemid = sli.itemid
WHERE
  le.valuenum IS NOT NULL
  -- restrict to labs taken on admission day (admittime through +1 day)
  AND le.charttime >= ha.admittime
  AND le.charttime <= TIMESTAMP_ADD(ha.admittime, INTERVAL 1 DAY)
;