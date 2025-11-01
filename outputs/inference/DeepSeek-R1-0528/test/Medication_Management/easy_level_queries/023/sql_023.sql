WITH ace_prescriptions AS (
  SELECT
    DATETIME_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pt
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pt.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON adm.subject_id = p.subject_id AND adm.hadm_id = p.hadm_id
  WHERE
    pt.gender = 'F'
    AND (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year + pt.anchor_age) BETWEEN 78 AND 88
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    AND REGEXP_CONTAINS(LOWER(p.drug), r'captopril|enalapril|lisinopril|ramipril|quinapril|perindopril|trandolapril|benazepril|fosinopril|moexipril')
)
SELECT
  STDDEV_POP(duration_days) AS sd_duration_days
FROM
  ace_prescriptions;