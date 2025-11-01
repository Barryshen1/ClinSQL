WITH hf_hadms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE ((icd_version = 9 AND icd_code LIKE '428%') 
         OR (icd_version = 10 AND icd_code LIKE 'I50%'))
),

cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN hf_hadms hf
    ON a.subject_id = hf.subject_id AND a.hadm_id = hf.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.dischtime IS NOT NULL
),

charlson_components AS (
  SELECT 
    c.hadm_id,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND (icd.icd_code LIKE '410%' OR icd.icd_code = '412')) 
            OR (icd.icd_version = 10 AND (icd.icd_code LIKE 'I21%' OR icd.icd_code LIKE 'I22%' OR icd.icd_code = 'I25.2')))
      THEN 1 ELSE 0 END) AS mi,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND icd.icd_code LIKE '428%') 
            OR (icd.icd_version = 10 AND (icd.icd_code IN ('I09.9', 'I11.0', 'I13.0', 'I13.2', 'I25.5') OR icd.icd_code LIKE 'I42%' OR icd.icd_code LIKE 'I50%')))
      THEN 1 ELSE 0 END) AS chf,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND (icd.icd_code LIKE '440%' OR icd.icd_code LIKE '441%' OR icd.icd_code LIKE '442%' OR icd.icd_code LIKE '443%' OR icd.icd_code LIKE '444%' OR icd.icd_code LIKE '445%' OR icd.icd_code LIKE '446%' OR icd.icd_code LIKE '447%' OR icd.icd_code LIKE '448%') AND icd.icd_code != '441.7') 
            OR (icd.icd_version = 10 AND (icd.icd_code LIKE 'I70%' OR icd.icd_code LIKE 'I71%' OR icd.icd_code LIKE 'I72%' OR icd.icd_code LIKE 'I73%' OR icd.icd_code = 'K55.1' OR icd.icd_code = 'K95.1' OR icd.icd_code LIKE 'T82.3%')))
      THEN 1 ELSE 0 END) AS pvd,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND icd.icd_code LIKE '43[0-8]%') 
            OR (icd.icd_version = 10 AND icd.icd_code LIKE 'I6[0-9]%'))
      THEN 1 ELSE 0 END) AS cva,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND (icd.icd_code LIKE '290.%' OR icd.icd_code LIKE '294.1%' OR icd.icd_code LIKE '331.[0-2]%')) 
            OR (icd.icd_version = 10 AND (icd.icd_code LIKE 'F0[1-3]%' OR icd.icd_code LIKE 'G30%')))
      THEN 1 ELSE 0 END) AS dementia,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND (icd.icd_code LIKE '490%' OR icd.icd_code LIKE '491%' OR icd.icd_code LIKE '492%' OR icd.icd_code LIKE '493%' OR icd.icd_code LIKE '494%' OR icd.icd_code LIKE '495%' OR icd.icd_code LIKE '496%' OR icd.icd_code LIKE '500%' OR icd.icd_code LIKE '501%' OR icd.icd_code LIKE '502%' OR icd.icd_code LIKE '503%' OR icd.icd_code LIKE '504%' OR icd.icd_code LIKE '505%' OR icd.icd_code = '508.1')) 
            OR (icd.icd_version = 10 AND (icd.icd_code LIKE 'J40%' OR icd.icd_code LIKE 'J41%' OR icd.icd_code LIKE 'J42%' OR icd.icd_code LIKE 'J43%' OR icd.icd_code LIKE 'J44%' OR icd.icd_code LIKE 'J47%' OR icd.icd_code LIKE 'J60%' OR icd.icd_code LIKE 'J61%' OR icd.icd_code LIKE 'J62%' OR icd.icd_code LIKE 'J63%' OR icd.icd_code LIKE 'J64%' OR icd.icd_code LIKE 'J65%' OR icd.icd_code LIKE 'J66%' OR icd.icd_code LIKE 'J67%')))
      THEN 1 ELSE 0 END) AS copd,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND (icd.icd_code LIKE '710%' OR icd.icd_code LIKE '711.2%' OR icd.icd_code LIKE '711.3%' OR icd.icd_code LIKE '714%' OR icd.icd_code = '725')) 
            OR (icd.icd_version = 10 AND (icd.icd_code LIKE 'M05%' OR icd.icd_code LIKE 'M06%' OR icd.icd_code LIKE 'M08%' OR icd.icd_code LIKE 'M12%' OR icd.icd_code LIKE 'M32%' OR icd.icd_code LIKE 'M33%' OR icd.icd_code LIKE 'M34%' OR icd.icd_code LIKE 'M35%' OR icd.icd_code = 'M45')))
      THEN 1 ELSE 0 END) AS rheum,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND (icd.icd_code LIKE '531%' OR icd.icd_code LIKE '532%' OR icd.icd_code LIKE '533%' OR icd.icd_code LIKE '534%' OR icd.icd_code LIKE '535%')) 
            OR (icd.icd_version = 10 AND (icd.icd_code LIKE 'K25%' OR icd.icd_code LIKE 'K26%' OR icd.icd_code LIKE 'K27%')))
      THEN 1 ELSE 0 END) AS pud,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND icd.icd_code LIKE '250.[0-3]%') 
            OR (icd.icd_version = 10 AND (icd.icd_code LIKE 'E[1-3][0-9].[0-1]%' OR icd.icd_code LIKE 'E[1-3][0-9].9%')))
      THEN 1 ELSE 0 END) AS dm,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND icd.icd_code LIKE '250.[4-6]%') 
            OR (icd.icd_version = 10 AND icd.icd_code LIKE 'E[1-3][0-9].[2-8]%'))
      THEN 1 ELSE 0 END) AS dmcomp,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND (icd.icd_code LIKE '342%' OR icd.icd_code LIKE '343%' OR icd.icd_code LIKE '344%')) 
            OR (icd.icd_version = 10 AND (icd.icd_code LIKE 'G81%' OR icd.icd_code LIKE 'G82%' OR icd.icd_code LIKE 'G83%' OR icd.icd_code LIKE 'G84.4')))
      THEN 1 ELSE 0 END) AS para,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND (icd.icd_code LIKE '582%' OR icd.icd_code LIKE '583%' OR icd.icd_code = '585' OR icd.icd_code = '586' OR icd.icd_code = '588.0' OR icd.icd_code = 'V42.0' OR icd.icd_code LIKE 'V45.1%' OR icd.icd_code LIKE 'V56%')) 
            OR (icd.icd_version = 10 AND (icd.icd_code LIKE 'I12%' OR icd.icd_code LIKE 'I13%' OR icd.icd_code LIKE 'N18%' OR icd.icd_code LIKE 'N19%' OR icd.icd_code = 'N25.5' OR icd.icd_code = 'Z94.0' OR icd.icd_code LIKE 'Z99.2%')))
      THEN 1 ELSE 0 END) AS renal,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND (icd.icd_code BETWEEN '140' AND '208')) 
            OR (icd.icd_version = 10 AND icd.icd_code LIKE 'C%'))
      THEN 1 ELSE 0 END) AS cancer,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND icd.icd_code BETWEEN '196' AND '199') 
            OR (icd.icd_version = 10 AND (icd.icd_code LIKE 'C77%' OR icd.icd_code LIKE 'C78%' OR icd.icd_code LIKE 'C79%' OR icd.icd_code = 'C80')))
      THEN 1 ELSE 0 END) AS metacancer,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND (icd.icd_code LIKE '456.[0-2]%' OR icd.icd_code = '572.3' OR icd.icd_code = '572.4' OR icd.icd_code = '572.8' OR icd.icd_code = '573.5')) 
            OR (icd.icd_version = 10 AND (icd.icd_code LIKE 'B18.2%' OR icd.icd_code LIKE 'I85%' OR icd.icd_code LIKE 'I86.4%' OR icd.icd_code LIKE 'K70%' OR icd.icd_code LIKE 'K71%' OR icd.icd_code LIKE 'K73%' OR icd.icd_code LIKE 'K74%' OR icd.icd_code = 'K76.6' OR icd.icd_code = 'K76.7' OR icd.icd_code = 'Z94.4')))
      THEN 1 ELSE 0 END) AS liver,
    MAX(CASE 
      WHEN ((icd.icd_version = 9 AND (icd.icd_code = '042' OR icd.icd_code LIKE '043%' OR icd.icd_code LIKE '044%')) 
            OR (icd.icd_version = 10 AND icd.icd_code LIKE 'B2[0-4]%'))
      THEN 1 ELSE 0 END) AS hiv
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` icd
    ON c.subject_id = icd.subject_id AND c.hadm_id = icd.hadm_id
  GROUP BY c.hadm_id
),

charlson AS (
  SELECT 
    c.*,
    (COALESCE(cc.mi, 0) * 1 + COALESCE(cc.chf, 0) * 1 + COALESCE(cc.pvd, 0) * 1 
     + COALESCE(cc.cva, 0) * 1 + COALESCE(cc.dementia, 0) * 1 + COALESCE(cc.copd, 0) * 1 
     + COALESCE(cc.rheum, 0) * 1 + COALESCE(cc.pud, 0) * 1 + COALESCE(cc.dm, 0) * 1 
     + COALESCE(cc.dmcomp, 0) * 2 + COALESCE(cc.para, 0) * 2 + COALESCE(cc.renal, 0) * 2 
     + (COALESCE(cc.cancer, 0) * 2 + COALESCE(cc.metacancer, 0) * 4) + COALESCE(cc.liver, 0) * 3 
     + COALESCE(cc.hiv, 0) * 6) AS charlson_score
  FROM cohort c
  LEFT JOIN charlson_components cc ON c.hadm_id = cc.hadm_id
),

icu_hadms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

vent_hadms AS (
  SELECT DISTINCT i.subject_id, i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ce.stay_id = i.stay_id
  WHERE ce.itemid IN (720, 1486, 535, 543, 224009, 224120, 224121, 224122, 224123, 224124, 224125, 224126, 224127, 224128, 224129, 223848, 223849, 223850, 223851, 223852, 223853, 223854, 223855, 223856, 223857, 223858, 223859)
    AND ce.valuenum IS NOT NULL
),

vaso_hadms AS (
  SELECT DISTINCT i.subject_id, i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ie.stay_id = i.stay_id
  WHERE ie.itemid IN (220615, 30047, 30120, 30044, 30046, 30307, 30309, 220606, 225907, 221906, 30052, 30053, 30125, 225958, 225966)
    AND (ie.rate > 0 OR ie.amount > 0)
    AND ie.ordercategoryname LIKE '%Infusion%'
),

rrt_hadms AS (
  SELECT DISTINCT i.subject_id, i.hadm_id
  FROM (
    SELECT stay_id FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    WHERE pe.itemid IN (225826, 225807, 225825, 228369, 228353)
    UNION DISTINCT
    SELECT ie.stay_id FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    WHERE ie.itemid IN (225798, 225849, 225850, 225851, 225853)
      AND (ie.rate > 0 OR ie.amount > 0)
  ) procs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON procs.stay_id = i.stay_id
),

outcomes_flags AS (
  SELECT 
    ch.*,
    CASE WHEN iu.subject_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_group,
    CASE WHEN ch.los_days <= 7 THEN '<=7' ELSE '>7' END AS los_group,
    CASE 
      WHEN COALESCE(ch.charlson_score, 0) <= 1 THEN '0-1'
      WHEN COALESCE(ch.charlson_score, 0) = 2 THEN '2'
      ELSE '>=3' 
    END AS charlson_group,
    CASE WHEN v.subject_id IS NOT NULL THEN 1 ELSE 0 END AS had_vent,
    CASE WHEN va.subject_id IS NOT NULL THEN 1 ELSE 0 END AS had_vaso,
    CASE WHEN r.subject_id IS NOT NULL THEN 1 ELSE 0 END AS had_rrt
  FROM charlson ch
  LEFT JOIN icu_hadms iu ON ch.subject_id = iu.subject_id AND ch.hadm_id = iu.hadm_id
  LEFT JOIN vent_hadms v ON ch.subject_id = v.subject_id AND ch.hadm_id = v.hadm_id
  LEFT JOIN vaso_hadms va ON ch.subject_id = va.subject_id AND ch.hadm_id = va.hadm_id
  LEFT JOIN rrt_hadms r ON ch.subject_id = r.subject_id AND ch.hadm_id = r.hadm_id
),

aggregated AS (
  SELECT 
    icu_group,
    los_group,
    charlson_group,
    COUNT(*) AS n,
    SUM(hospital_expire_flag) AS deaths,
    SUM(had_vent) AS vent_count,
    SUM(had_vaso) AS vaso_count,
    SUM(had_rrt) AS rrt_count
  FROM outcomes_flags
  GROUP BY icu_group, los_group, charlson_group
)

SELECT 
  icu_group,
  los_group,
  charlson_group,
  n,
  ROUND((deaths / n * 100), 2) AS mort_pct,
  ROUND(((deaths / n - 1.96 * SQRT((deaths / n) * (1 - deaths / n) / n)) * 100), 2) AS mort_ci_low,
  ROUND(((deaths / n + 1.96 * SQRT((deaths / n) * (1 - deaths / n) / n)) * 100), 2) AS mort_ci_high,
  ROUND((vent_count / n * 100), 2) AS vent_pct,
  ROUND((vaso_count / n * 100), 2) AS vaso_pct,
  ROUND((rrt_count / n * 100), 2) AS rrt_pct
FROM aggregated
WHERE n > 0
ORDER BY icu_group, los_group, charlson_group;