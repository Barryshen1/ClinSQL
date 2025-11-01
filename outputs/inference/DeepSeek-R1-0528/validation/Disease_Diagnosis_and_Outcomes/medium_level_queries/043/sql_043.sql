WITH cohort AS (
  SELECT 
      a.subject_id, 
      a.hadm_id, 
      a.admittime, 
      a.dischtime,
      a.hospital_expire_flag,
      p.gender,
      p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 44 AND 54
      AND a.hadm_id IN (
          SELECT hadm_id 
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
          WHERE 
              (icd_version = 9 AND icd_code LIKE '428%') OR
              (icd_version = 10 AND icd_code LIKE 'I50%')
      )
),

icu_flag AS (
  SELECT 
      c.*,
      CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'no ICU' END AS icu_status
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON c.hadm_id = i.hadm_id
),

comorbidity_flags AS (
  SELECT 
      hadm_id,
      MAX(CASE 
          WHEN (icd_version = 9 AND SUBSTR(icd_code,1,3) IN ('410','412'))
             OR (icd_version = 10 AND (SUBSTR(icd_code,1,3) IN ('I21','I22') OR icd_code = 'I252'))
          THEN 1 ELSE 0 END) AS myocardial_infarct,
      MAX(CASE 
          WHEN (icd_version = 9 AND SUBSTR(icd_code,1,3) = '428'
                OR SUBSTR(icd_code,1,5) IN ('39891','40201','40211','40291','40401','40403','40411','40413','40491','40493')
                OR (SUBSTR(icd_code,1,3) = '425' AND CAST(SUBSTR(icd_code,5,2) AS INT) BETWEEN 4 AND 9)
          OR (icd_version = 10 AND (SUBSTR(icd_code,1,3) IN ('I43','I50')
                OR SUBSTR(icd_code,1,4) IN ('I099','I110','I130','I132','I255','I420','I425','I426','I427','I428','I429','P290'))
          THEN 1 ELSE 0 END) AS congestive_heart_failure,
      MAX(CASE 
          WHEN (icd_version = 9 AND SUBSTR(icd_code,1,3) IN ('440','441')
                OR SUBSTR(icd_code,1,4) IN ('4431','4432','4438','4439','7854','V434')
                OR SUBSTR(icd_code,1,3) BETWEEN '440' AND '449'
          OR (icd_version = 10 AND SUBSTR(icd_code,1,3) IN ('I70','I71')
                OR SUBSTR(icd_code,1,3) = 'I73'
                OR SUBSTR(icd_code,1,4) IN ('I771','I790','I792','K551','K558','K559','Z958','Z959'))
          THEN 1 ELSE 0 END) AS peripheral_vascular_disease,
      MAX(CASE 
          WHEN (icd_version = 9 AND SUBSTR(icd_code,1,3) IN ('430','431','432','433','434','435','436','437','438')
          OR (icd_version = 10 AND SUBSTR(icd_code,1,3) IN ('G45','G46','I60','I61','I62','I63','I64','I65','I66','I67','I68','I69')
                OR SUBSTR(icd_code,1,4) = 'H340')
          THEN 1 ELSE 0 END) AS cerebrovascular_disease,
      MAX(CASE 
          WHEN (icd_version = 9 AND SUBSTR(icd_code,1,3) = '290'
                OR SUBSTR(icd_code,1,4) IN ('2941','3312')
          OR (icd_version = 10 AND SUBSTR(icd_code,1,3) IN ('F00','F01','F02','F03','G30')
                OR SUBSTR(icd_code,1,4) IN ('F051','G311'))
          THEN 1 ELSE 0 END) AS dementia,
      MAX(CASE 
          WHEN (icd_version = 9 AND (SUBSTR(icd_code,1,3) IN ('490','491','492','493','494','495','496','497','498','499','500','501','502','503','504','505')
                OR SUBSTR(icd_code,1,4) IN ('4168','4169','5064','5081','5088'))
          OR (icd_version = 10 AND (SUBSTR(icd_code,1,3) IN ('J40','J41','J42','J43','J44','J45','J46','J47','J60','J61','J62','J63','J64','J65','J66','J67')
                OR SUBSTR(icd_code,1,4) IN ('I278','I279','J684','J701','J703'))
          THEN 1 ELSE 0 END) AS chronic_pulmonary_disease,
      MAX(CASE 
          WHEN (icd_version = 9 AND SUBSTR(icd_code,1,3) IN ('710','711','712','713','714','715','716','717','718','719','720','725')
          OR (icd_version = 10 AND SUBSTR(icd_code,1,3) IN ('M05','M06','M32','M33','M34','M351','M353','M360')
          THEN 1 ELSE 0 END) AS rheumatic_disease,
      MAX(CASE 
          WHEN (icd_version = 9 AND SUBSTR(icd_code,1,3) IN ('531','532','533','534')
          OR (icd_version = 10 AND SUBSTR(icd_code,1,3) IN ('K25','K26','K27','K28')
          THEN 1 ELSE 0 END) AS peptic_ulcer_disease,
      MAX(CASE 
          WHEN (icd_version = 9 AND SUBSTR(icd_code,1,3) IN ('570','571')
                OR SUBSTR(icd_code,1,4) IN ('0706','0709','07022','07023','07032','07033','07044','07054')
                OR SUBSTR(icd_code,1,5) IN ('07020','07021','07022','07023','07030','07031','07032','07033','07044','07054','5733','5734','V427')
          OR (icd_version = 10 AND SUBSTR(icd_code,1,3) IN ('B18','K73','K74')
                OR SUBSTR(icd_code,1,4) IN ('K700','K701','K702','K703','K709','K713','K714','K715','K717','K760','K762','K763','K764','K768','K769','Z944')
          THEN 1 ELSE 0 END) AS mild_liver_disease,
      MAX(CASE 
          WHEN (icd_version = 9 AND (SUBSTR(icd_code,1,4) IN ('2500','2501','2502','2503','2508','2509')
          OR (icd_version = 10 AND (SUBSTR(icd_code,1,4) IN ('E100','E101','E106','E108','E109','E110','E111','E116','E118','E119','E120','E121','E126','E128','E129','E130','E131','E136','E138','E139','E140','E141','E146','E148','E149')
          THEN 1 ELSE 0 END) AS diabetes_without_cc,
      MAX(CASE 
          WHEN (icd_version = 9 AND SUBSTR(icd_code,1,4) IN ('2504','2505','2506','2507')
          OR (icd_version = 10 AND SUBSTR(icd_code,1,4) IN ('E102','E103','E104','E105','E107','E112','E113','E114','E115','E117','E122','E123','E124','E125','E127','E132','E133','E134','E135','E137','E142','E143','E144','E145','E147')
          THEN 1 ELSE 0 END) AS diabetes_with_cc,
      MAX(CASE 
          WHEN (icd_version = 9 AND SUBSTR(icd_code,1,3) IN ('342','343')
                OR SUBSTR(icd_code,1,4) IN ('3341','3440','3441','3442','3443','3444','3445','3446','3449')
          OR (icd_version = 10 AND SUBSTR(icd_code,1,3) IN ('G81','G82')
                OR SUBSTR(icd_code,1,4) IN ('G041','G114','G801','G802','G830','G831','G832','G833','G834','G839')
          THEN 1 ELSE 0 END) AS paraplegia,
      MAX(CASE 
          WHEN (icd_version = 9 AND SUBSTR(icd_code,1,3) IN ('582','583','585','586','588')
                OR SUBSTR(icd_code,1,4) IN ('V420','V451','V56')
          OR (icd_version = 10 AND SUBSTR(icd_code,1,3) IN ('N18','N19')
                OR SUBSTR(icd_code,1,4) IN ('I120','I131','N032','N033','N034','N035','N036','N037','N052','N053','N054','N055','N056','N057','N250','Z490','Z491','Z492','Z940','Z992')
          THEN 1 ELSE 0 END) AS renal_disease,
      MAX(CASE 
          WHEN (icd_version = 9 AND SUBSTR(icd_code,1,3) IN ('140','141','142','143','144','145','146','147','148','149','150','151','152','153','154','155','156','157','158','159','160','161','162','163','164','165','166','167','168','169','170','171','172','174','175','176','177','178','179','180','181','182','183','184','185','186','187','188','189','190','191','192','193','194','195','196','197','198','199')
          OR (icd_version = 10 AND SUBSTR(icd_code,1,3) IN ('C0','C1','C2','C3','C4','C5','C6','C7','C8','C9')
                OR SUBSTR(icd_code,1,4) IN ('D00','D01','D02','D03','D04','D05','D06','D07','D08','D09')
          THEN 1 ELSE 0 END) AS any_malignancy,
      MAX(CASE 
          WHEN (icd_version = 9 AND SUBSTR(icd_code,1,3) IN ('456','572')
                OR SUBSTR(icd_code,1,4) IN ('5672','5673','5674','5678','5679')
          OR (icd_version = 10 AND SUBSTR(icd_code,1,4) IN ('I850','I859','I864','I982','K704','K711','K721','K729','K765','K766','K767')
          THEN 1 ELSE 0 END) AS severe_liver_disease,
      MAX(CASE 
          WHEN (icd_version = 9 AND SUBSTR(icd_code,1,3) IN ('196','197','198','199')
          OR (icd_version = 10 AND SUBSTR(icd_code,1,3) IN ('C77','C78','C79','C80')
          THEN 1 ELSE 0 END) AS metastatic_solid_tumor,
      MAX(CASE 
          WHEN (icd_version = 9 AND SUBSTR(icd_code,1,3) IN ('042','043','044')
          OR (icd_version = 10 AND SUBSTR(icd_code,1,3) IN ('B20','B21','B22','B24')
          THEN 1 ELSE 0 END) AS aids
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

charlson_data AS (
  SELECT 
      hadm_id,
      myocardial_infarct * 1 +
      congestive_heart_failure * 1 +
      peripheral_vascular_disease * 1 +
      cerebrovascular_disease * 1 +
      dementia * 1 +
      chronic_pulmonary_disease * 1 +
      rheumatic_disease * 1 +
      peptic_ulcer_disease * 1 +
      mild_liver_disease * 1 +
      diabetes_without_cc * 1 +
      diabetes_with_cc * 2 +
      paraplegia * 2 +
      renal_disease * 2 +
      any_malignancy * 2 +
      severe_liver_disease * 3 +
      metastatic_solid_tumor * 6 +
      aids * 6 AS charlson_score
  FROM comorbidity_flags
),

interventions AS (
  SELECT 
      i.hadm_id,
      MAX(CASE WHEN pe.itemid IN (225468, 227194) THEN 1 ELSE 0 END) AS mech_vent,
      MAX(CASE WHEN mv.itemid IN (221906, 221289, 221662, 221749, 222315) THEN 1 ELSE 0 END) AS vasopressor,
      MAX(CASE WHEN pe_rrt.itemid IN (225802, 225803, 225809) THEN 1 ELSE 0 END) AS rrt
  FROM icu_flag i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu 
      ON i.hadm_id = icu.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
      ON icu.stay_id = pe.stay_id AND pe.itemid IN (225468, 227194)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` mv 
      ON icu.stay_id = mv.stay_id AND mv.itemid IN (221906, 221289, 221662, 221749, 222315)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe_rrt 
      ON icu.stay_id = pe_rrt.stay_id AND pe_rrt.itemid IN (225802, 225803, 225809)
  WHERE i.icu_status = 'ICU'
  GROUP BY i.hadm_id
),

combined AS (
  SELECT 
      i.*,
      DATETIME_DIFF(i.dischtime, i.admittime, DAY) AS los_days,
      COALESCE(c.charlson_score, 0) AS charlson_score,
      COALESCE(iv.mech_vent, 0) AS mech_vent,
      COALESCE(iv.vasopressor, 0) AS vasopressor,
      COALESCE(iv.rrt, 0) AS rrt
  FROM icu_flag i
  LEFT JOIN charlson_data c 
      ON i.hadm_id = c.hadm_id
  LEFT JOIN interventions iv 
      ON i.hadm_id = iv.hadm_id
),

cohort_groups AS (
  SELECT 
      *,
      CASE 
          WHEN los_days <= 7 THEN '<=7'
          ELSE '>7'
      END AS los_group,
      CASE 
          WHEN charlson_score <= 1 THEN '0-1'
          WHEN charlson_score = 2 THEN '2'
          ELSE '>=3'
      END AS charlson_group
  FROM combined
),

agg AS (
  SELECT 
      icu_status,
      los_group,
      charlson_group,
      COUNT(*) AS n,
      AVG(hospital_expire_flag) AS mortality_prop,
      AVG(mech_vent) AS mech_vent_prop,
      AVG(vasopressor) AS vasopressor_prop,
      AVG(rrt) AS rrt_prop
  FROM cohort_groups
  GROUP BY icu_status, los_group, charlson_group
)

SELECT 
    icu_status,
    los_group,
    charlson_group,
    n,
    CONCAT(
        ROUND(mortality_prop * 100, 1), 
        '% [', 
        ROUND(GREATEST(0, (mortality_prop - 1.96 * SQRT(mortality_prop * (1 - mortality_prop) / n)) * 100), 1),
        '%, ',
        ROUND(LEAST(100, (mortality_prop + 1.96 * SQRT(mortality_prop * (1 - mortality_prop) / n)) * 100), 1),
        '%]'
    ) AS in_hospital_mortality,
    ROUND(mech_vent_prop * 100, 1) AS mech_vent_rate,
    ROUND(vasopressor_prop * 100, 1) AS vasopressor_rate,
    ROUND(rrt_prop * 100, 1) AS rrt_rate
FROM agg
ORDER BY icu_status, los_group, charlson_group;