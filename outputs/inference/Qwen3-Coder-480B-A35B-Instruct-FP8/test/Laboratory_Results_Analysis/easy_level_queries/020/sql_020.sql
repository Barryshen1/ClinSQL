WITH hf_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 49
    AND LOWER(dd.long_title) LIKE '%heart failure%'
    AND d.seq_num = 1
),
nadir_hemoglobin AS (
  SELECT
    h.hadm_id,
    MIN(l.valuenum) AS nadir_hb
  FROM
    hf_admissions h
  JOIN
    physionet-data.mimiciv_3_1_hosp.labevents l
    ON h.hadm_id = l.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'hemoglobin'
    AND l.valuenum IS NOT NULL
    AND l.charttime BETWEEN h.admittime AND h.dischtime
  GROUP BY
    h.hadm_id
)
SELECT
  PERCENTILE_CONT(nadir_hb, 0.75) OVER() AS hemoglobin_75th_percentile
FROM
  nadir_hemoglobin
LIMIT 1;