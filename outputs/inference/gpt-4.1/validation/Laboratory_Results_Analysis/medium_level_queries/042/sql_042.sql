WITH chest_pain_admissions AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON adm.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
      ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 84 AND 94
    AND (
      LOWER(ddx.long_title) LIKE '%chest pain%'
      OR dx.icd_code IN ('78650','78651','78652','78659') -- ICD-9 chest pain
      OR dx.icd_code LIKE 'R07%' -- ICD-10 chest pain
    )
),

troponin_labs AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom,
    dl.label
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
      ON le.itemid = dl.itemid
  WHERE
    LOWER(dl.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
),

first_troponin AS (
  SELECT
    cpa.subject_id,
    cpa.hadm_id,
    cpa.gender,
    cpa.anchor_age,
    cpa.hospital_expire_flag,
    tl.charttime,
    tl.valuenum,
    tl.valueuom
  FROM
    chest_pain_admissions cpa
    JOIN (
      SELECT
        hadm_id,
        MIN(charttime) AS first_charttime
      FROM troponin_labs
      GROUP BY hadm_id
    ) first_lab
      ON cpa.hadm_id = first_lab.hadm_id
    JOIN troponin_labs tl
      ON cpa.hadm_id = tl.hadm_id
      AND tl.charttime = first_lab.first_charttime
)

SELECT
  CASE
    WHEN ft.valuenum <= 0.01 THEN 'Normal'
    WHEN ft.valuenum > 0.01 AND ft.valuenum <= 0.03 THEN 'Borderline'
    WHEN ft.valuenum > 0.03 THEN 'Elevated'
    ELSE 'Unknown'
  END AS troponin_category,
  COUNT(*) AS admission_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percent_of_total,
  SUM(CASE WHEN ft.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS died_in_hospital,
  ROUND(SUM(CASE WHEN ft.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS percent_died_in_hospital
FROM
  first_troponin ft
GROUP BY
  troponin_category
ORDER BY
  troponin_category;