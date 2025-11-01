WITH pneumonia_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
      ON d.icd_code = diag.icd_code
      AND d.icd_version = diag.icd_version
  WHERE
    LOWER(diag.long_title) LIKE '%pneumonia%'
),
elderly_male_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN pneumonia_admissions pa
      ON a.hadm_id = pa.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age >= 95
),
peak_creatinine AS (
  SELECT
    l.hadm_id,
    MAX(l.valuenum) AS peak_creat
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
      ON l.itemid = li.itemid
  WHERE
    l.valuenum IS NOT NULL
    AND LOWER(li.label) LIKE '%creatinine%'
  GROUP BY
    l.hadm_id
),
cohort_creat AS (
  SELECT
    pc.peak_creat
  FROM
    peak_creatinine pc
    JOIN elderly_male_cohort emc
      ON pc.hadm_id = emc.hadm_id
)
SELECT
  STDDEV_SAMP(peak_creat) AS sd_peak_creatinine
FROM
  cohort_creat;