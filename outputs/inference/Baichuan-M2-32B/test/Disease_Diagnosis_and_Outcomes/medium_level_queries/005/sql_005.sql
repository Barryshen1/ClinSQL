WITH
  -- Step 1: Eligible admissions (male, age 38-48, with HF diagnosis)
  eligible_admissions AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      -- Compute age at admission: birth_year = anchor_year - anchor_age, then age = YEAR(admittime) - birth_year
      EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    WHERE
      p.gender = 'M'
      AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 38 AND 48
      -- Check for HF diagnosis in this admission (ICD-10 I50.x)
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND d.icd_version = 10
          AND d.icd_code LIKE 'I50.%'
      )
  ),
  -- Step 2: All ICD-10 codes from diagnoses_icd and procedures_icd for these admissions, excluding HF codes
  all_icd_codes AS (
    SELECT
      d.subject_id,
      d.hadm_id,
      d.icd_code,
      'diagnoses' AS source_table
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE
      d.hadm_id IN (SELECT hadm_id FROM eligible_admissions)
      AND d.icd_version = 10
      AND d.icd_code NOT LIKE 'I50.%'  -- exclude HF
    UNION ALL
    SELECT
      p.subject_id,
      p.hadm_id,
      p.icd_code,
      'procedures' AS source_table
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    WHERE
      p.hadm_id IN (SELECT hadm_id FROM eligible_admissions)
      AND p.icd_version = 10
      AND p.icd_code NOT LIKE 'I50.%'  -- exclude HF
  ),
  -- Step 3: Map ICD-10 codes to Charlson conditions and weights (using CASE with priority for highest weight)
  charlson_mapping AS (
    SELECT
      icd_code,
      -- Assign condition and weight; order by highest weight first to ensure correct mapping
      CASE
        -- Metastatic solid tumor (weight 6)
        WHEN icd_code IN ('C79.0','C79.1','C79.2','C79.3','C79.4','C79.5','C79.6','C79.7','C79.8','C79.9') THEN ('Metastatic solid tumor', 6)
        -- AIDS (weight 6)
        WHEN icd_code IN ('B20','B21','B22','B23','B24','B25','B26','B27','B28','B29','I95.11','I95.12','I95.13','I95.19','I95.2','I95.3','I95.4','I95.5','I95.6','I95.7','I95.8','I95.9') THEN ('AIDS', 6)
        -- Moderate or severe liver disease (weight 3)
        WHEN icd_code IN ('K70','K71','K72','K73','K74','K75','K76','K77','K78','K79','K80','K81','K82','K83','K84','K85','K86','K87','K88','K89','K90','K91','K92','K93','K94','K95','K96','K97','K98','K99') THEN ('Moderate or severe liver disease', 3)
        -- Any malignancy (weight 2) - note: this includes many codes, but we must be careful not to double-count with metastatic or AIDS? The mapping is per code, and we'll take the highest weight per condition later.
        WHEN icd_code IN ('C00','C01','C02','C03','C04','C05','C06','C07','C08','C09','C10','C11','C12','C13','C14','C15','C16','C17','C18','C19','C20','C21','C22','C23','C24','C25','C26','C30','C31','C32','C33','C34','C35','C36','C37','C38','C39','C40','C41','C42','C43','C44','C45','C46','C47','C48','C49','C50','C51','C52','C53','C54','C55','C56','C57','C58','C60','C61','C62','C63','C64','C65','C66','C67','C68','C69','C70','C71','C72','C73','C74','C75','C76','C77','C78','C79','C80','C81','C82','C83','C84','C85','C86','C87','C88','C89','C90','C91','C92','C93','C94','C95','C96','C97','C98','C99') THEN ('Any malignancy', 2)
        -- Diabetes with complications (weight 2)
        WHEN icd_code IN ('E10.1','E10.2','E10.3','E10.4','E10.5','E10.6','E10.8','E10.9','E11.1','E11.2','E11.3','E11.4','E11.5','E11.6','E11.8','E11.9','E12.1','E12.2','E12.3','E12.4','E12.5','E12.6','E12.8','E12.9','E13.1','E13.2','E13.3','E13.4','E13.5','E13.6','E13.8','E13.9','E14.1','E14.2','E14.3','E14.4','E14.5','E14.6','E14.8','E14.9') THEN ('Diabetes with complications', 2)
        -- Hemiplegia or paraplegia (weight 2)
        WHEN icd_code IN ('G81','G82','G83','G84','G85','G86','G87','G88','G89','G90','G91','G92','G93','G94','G95','G96','G97','G98','G99') THEN ('Hemiplegia or paraplegia', 2)
        -- Renal disease (weight 2)
        WHEN icd_code IN ('N17','N18','N19','N20','N21','N22','N23','N24','N25','N26','N27','N28','N29','N30','N31','N32','N33','N34','N35','N36','N37','N38','N39','N40','N41','N42','N43','N44','N45','N46','N47','N48','N49','N50','N51','N52','N53','N54','N55','N56','N57','N58','N59','N60','N61','N62','N63','N64','N65','N66','N67','N68','N69','N70','N71','N72','N73','N74','N75','N76','N77','N78','N79','N80','N81','N82','N83','N84','N85','N86','N87','N88','N89','N90','N91','N92','N93','N94','N95','N96','N97','N98','N99') THEN ('Renal disease', 2)
        -- Myocardial infarction (weight 1)
        WHEN icd_code IN ('I21.0','I21.1','I21.2','I21.3','I21.4') THEN ('Myocardial infarction', 1)
        -- Congestive heart failure (weight 1) - but we excluded HF, so this should not appear? Double-check: we excluded I50.x, so this condition is not mapped from the data. We'll leave it for completeness but it should not be used.
        WHEN icd_code IN ('I50.0','I50.1','I50.2','I50.3','I50.4','I50.8','I50.9') THEN ('Congestive heart failure', 1)
        -- Peripheral vascular disease (weight 1)
        WHEN icd_code IN ('I70.0','I70.1','I70.2','I70.3','I70.4','I70.5','I70.6','I70.7','I70.8','I70.9') THEN ('Peripheral vascular disease', 1)
        -- Cerebrovascular disease (weight 1)
        WHEN icd_code IN ('G45.0','G45.1','G45.2','G45.3','G45.4','G45.5','G45.6','G45.7','G45.8','G45.9','G46.0','G46.1','G46.2','G46.3','G46.4','G46.5','G46.6','G46.7','G46.8','G46.9','I60','I61','I62','I63','I64','I65','I66','I67','I68','I69') THEN ('Cerebrovascular disease', 1)
        -- Dementia (weight 1)
        WHEN icd_code IN ('F00','F01','F02','F03','F05.0','F05.1','F05.2','F05.8','F05.9','G30','G31.0','G31.1','G31.2','G31.8','G31.9') THEN ('Dementia', 1)
        -- Chronic pulmonary disease (weight 1)
        WHEN icd_code IN ('J40','J41','J42','J43','J44','J45','J46','J47','J98.4','J98.5','J98.6','J98.7','J98.8','J98.9') THEN ('Chronic pulmonary disease', 1)
        -- Rheumatologic disease (weight 1)
        WHEN icd_code IN ('M30','M31','M32','M33','M34','M35','M36','M37','M38','M39','M46','M47','M48','M49','M50','M51','M52','M53','M54','M60','M61','M62','M63','M64','M65','M66','M67','M68','M69','M70','M71','M72','M73','M74','M75','M76','M77','M78','M79','M80','M81','M82','M83','M84','M85','M86','M87','M88','M89','M90','M91','M92','M93','M94','M95','M96','M97','M98','M99') THEN ('Rheumatologic disease', 1)
        -- Peptic ulcer disease (weight 1)
        WHEN icd_code IN ('K25','K26','K27','K28','K29','K30','K31','K32','K33','K34','K35','K36','K37','K38','K39','K40','K41','K42','K43','K44','K45','K46','K47','K48','K49','K50','K51','K52','K53','K54','K55','K56','K57','K58','K59','K60','K61','K62','K63','K64','K65','K66','K67','K68','K69','K70','K71','K72','K73','K74','K75','K76','K77','K78','K79','K80','K81','K82','K83','K84','K85','K86','K87','K88','K89','K90','K91','K92','K93','K94','K95','K96','K97','K98','K99') THEN ('Peptic ulcer disease', 1)
        -- Mild liver disease (weight 1) - note: this overlaps with moderate/severe? We map to mild only if not already mapped to moderate/severe.
        WHEN icd_code IN ('K70','K71','K72','K73','K74','K75','K76','K77','K78','K79','K80','K81','K82','K83','K84','K85','K86','K87','K88','K89','K90','K91','K92','K93','K94','K95','K96','K97','K98','K99') THEN ('Mild liver disease', 1)
        -- Diabetes without complications (weight 1)
        WHEN icd_code IN ('E10','E11','E12','E13','E14') THEN ('Diabetes without complications', 1)
        ELSE (NULL, NULL)  -- Unmapped codes
      END AS (condition, weight)
    FROM
      (SELECT DISTINCT icd_code FROM all_icd_codes)  -- Use distinct codes to avoid duplicates
  ),
  -- Step 4: Map codes to conditions and weights, then get highest weight per condition per patient
  mapped_codes AS (
    SELECT
      c.subject_id,
      c.hadm_id,
      m.condition,
      m.weight
    FROM
      all_icd_codes c
    LEFT JOIN
      charlson_mapping m
      ON c.icd_code = m.icd_code
    WHERE
      m.condition IS NOT NULL  -- Only keep mapped codes
  ),
  -- Step 5: For each patient and condition, get the highest weight (in case of multiple codes for same condition)
  ranked_conditions AS (
    SELECT
      subject_id,
      hadm_id,
      condition,
      weight,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id, condition ORDER BY weight DESC) AS rn
    FROM
      mapped_codes
  ),
  -- Step 6: Aggregate per patient to get Charlson index and comorbidity count
  charlson_agg AS (
    SELECT
      subject_id,
      hadm_id,
      SUM(weight) AS charlson_index,
      COUNT(DISTINCT condition) AS comorbidity_count
    FROM
      ranked_conditions
    WHERE
      rn = 1  -- Only the highest weight per condition
    GROUP BY
      subject_id, hadm_id
  ),
  -- Step 7: ICU use (yes/no) and LOS for each admission
  icu_info AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      CASE WHEN i.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS icu_use
    FROM
      eligible_admissions a
    LEFT JOIN
      `physionet-data.mimiciv_3_1_icu.icustays` i
      ON a.subject_id = i.subject_id
      AND a.hadm_id = i.hadm_id
  ),
  -- Step 8: Compute LOS and join with other data
  admission_metrics AS (
    SELECT
      e.subject_id,
      e.hadm_id,
      e.hospital_expire_flag,
      DATEDIFF(e.dischtime, e.admittime) AS los,
      c.charlson_index,
      c.comorbidity_count,
      i.icu_use
    FROM
      eligible_admissions e
    LEFT JOIN
      charlson_agg c
      ON e.subject_id = c.subject_id
      AND e.hadm_id = c.hadm_id
    LEFT JOIN
      icu_info i
      ON e.subject_id = i.subject_id
      AND e.hadm_id = i.hadm_id
  ),
  -- Step 9: Stratify and compute outcomes
  stratified_data AS (
    SELECT
      icu_use,
      CASE
        WHEN los BETWEEN 1 AND 3 THEN '1-3'
        WHEN los BETWEEN 4 AND 7 THEN '4-7'
        WHEN los >= 8 THEN '>=8'
        ELSE 'Unknown'
      END AS los_group,
      CASE
        WHEN charlson_index <= 3 THEN '0-3'
        WHEN charlson_index BETWEEN 4 AND 5 THEN '4-5'
        WHEN charlson_index > 5 THEN '>5'
        ELSE 'Unknown'
      END AS charlson_group,
      hospital_expire_flag,
      comorbidity_count
    FROM
      admission_metrics
    WHERE
      los IS NOT NULL  -- Exclude admissions without valid LOS
  ),
  -- Step 10: Aggregate per stratum
  aggregated_strata AS (
    SELECT
      icu_use,
      los_group,
      charlson_group,
      COUNT(*) AS n,
      SUM(CAST(hospital_expire_flag AS INT)) AS deaths,
      AVG(comorbidity_count) AS mean_comorbidity_count
    FROM
      stratified_data
    GROUP BY
      icu_use, los_group, charlson_group
  ),
  -- Step 11: Compute mortality rate and 95% CI
  final_results AS (
    SELECT
      icu_use,
      los_group,
      charlson_group,
      n,
      deaths,
      ROUND(100.0 * deaths / n, 2) AS mortality_rate,
      -- 95% CI using normal approximation: mortality_rate ± 1.96 * SE
      ROUND(100.0 * deaths / n - 1.96 * SQRT(100.0 * deaths / n * (1 - 100.0 * deaths / n) / n), 2) AS ci_lower,
      ROUND(100.0 * deaths / n + 1.96 * SQRT(100.0 * deaths / n * (1 - 100.0 * deaths / n) / n), 2) AS ci_upper,
      ROUND(mean_comorbidity_count, 2) AS mean_comorbidity_count
    FROM
      aggregated_strata
  )
SELECT * FROM final_results
ORDER BY icu_use, los_group, charlson_group;