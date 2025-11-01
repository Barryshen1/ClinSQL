SELECT
  MIN(admission_min_sodium) AS min_sodium
FROM (
  SELECT
    a.hadm_id,
    MIN(le.valuenum) AS admission_min_sodium
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
  ON
    p.subject_id = a.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
  ON
    d.icd_code = did.icd_code
    AND d.icd_version = did.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.labevents le
  ON
    a.hadm_id = le.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems dl
  ON
    le.itemid = dl.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age >= 65
    AND LOWER(did.long_title) LIKE '%heart failure%'
    AND LOWER(dl.label) = 'sodium'
    AND LOWER(dl.fluid) = 'blood'
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN a.admittime AND a.dischtime
  GROUP BY
    a.hadm_id
);