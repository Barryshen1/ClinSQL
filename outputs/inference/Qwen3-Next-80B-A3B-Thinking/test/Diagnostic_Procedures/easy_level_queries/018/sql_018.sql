WITH patients_in_group AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 86 AND 96
),
hosp_procedures AS (
  SELECT pi.subject_id, COUNT(*) AS count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%catheter ablation%'
     OR LOWER(dip.long_title) LIKE '%cardioversion%'
  GROUP BY pi.subject_id
),
icu_procedures AS (
  SELECT pe.subject_id, COUNT(*) AS count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%catheter ablation%'
     OR LOWER(di.label) LIKE '%cardioversion%'
  GROUP BY pe.subject_id
),
combined_counts AS (
  SELECT 
    pg.subject_id,
    COALESCE(h.count, 0) + COALESCE(i.count, 0) AS total_procedures
  FROM patients_in_group pg
  LEFT JOIN hosp_procedures h ON pg.subject_id = h.subject_id
  LEFT JOIN icu_procedures i ON pg.subject_id = i.subject_id
)
SELECT STDDEV(total_procedures) AS sd_procedures
FROM combined_counts;