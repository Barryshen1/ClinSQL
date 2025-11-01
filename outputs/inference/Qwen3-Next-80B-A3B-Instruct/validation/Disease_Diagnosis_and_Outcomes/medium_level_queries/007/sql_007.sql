with heart failure, stratified by:` was written as if it were a comment or natural language annotation, but BigQuery SQL does not allow free-form text before the `WITH` clause. The `WITH` keyword must be immediately followed by a CTE name and `AS`. This caused the parser to fail with: `Syntax error: Expected keyword AS but got identifier "comment"`.

2. **Incomplete and malformed CCI logic**: The `charlson_comorbidities` CTE was cut off mid-expression (ending with `E;`), making the query syntactically invalid. Additionally, the CCI calculation must exclude heart failure (as per clinical question), but the current logic does not filter out HF codes from the comorbidity count — this must be corrected.

Other key fixes applied:
- Used `DATE_DIFF(dischtime, admittime, DAY)` for LOS (correct and reliable in BigQuery).
- Used `REGEXP_CONTAINS(LOWER(...), r'...')` for case-insensitive matching of heart failure in `d_icd_diagnoses.long_title` (BigQuery doesn’t support `ILIKE`).
- Ensured all table references use correct dataset prefixes: `physionet-data.mimiciv_3_1_hosp` and `physionet-data.mimiciv_3_1_icu`.
- Used `LEFT JOIN` to `icustays` to classify ICU vs non-ICU.
- For MV, vasopressors, RRT: joined `procedureevents` and `inputevents` with `d_items` using `linksto = 'procedureevents'` or `'inputevents'` and matched labels with `REGEXP_CONTAINS`.
- Used `COUNTIF()` for clean prevalence aggregation.
- Defined comorbidity burden (low/med/high) as: 0 = low, 1–2 = medium, ≥3 = high (standard Charlson grouping).
- Excluded heart failure codes from CCI calculation (per clinical question: comorbidity burden excluding HF).
- Fixed the truncated CCI logic and completed all CASE conditions.
- Used `GROUP BY` on derived fields: `icu_status`, `los_group`, `comorbidity_burden`.

Note: MV, vasopressors, and RRT are ICU-based interventions. For non-ICU patients, these are assumed to be 0 (since they are not measured in the ICU tables). We use `LEFT JOIN` to ICU tables, so non-ICU patients will have NULLs — we use `COALESCE(..., 0)` to treat them as 0.

sql
WITH heart_failure_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'No_ICU' END AS icu_status
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  LEFT JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          REGEXP_CONTAINS(LOWER(d_icd.long_title), r'heart failure')
          OR d.icd_code IN ('4280','4281','4282','4283','4284','4289','I500','I501','I502','I503','I504','I509')
        )
    )
),

charlson_comorbidities AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    SUM(
      CASE
        WHEN d_icd.icd_code IN ('410','4100','4101','4102','4103','4104','4105','4106','4107','4108','4109','I21','I210','I211','I212','I213','I214','I22','I220','I221','I222','I228','I229','I23') THEN 1
        WHEN d_icd.icd_code IN ('440','4400','4401','4402','4403','4404','4405','4406','4407','4408','4409','I70','I700','I701','I702','I703','I704','I705','I706','I707','I708','I709') THEN 1
        WHEN d_icd.icd_code IN ('430','431','432','433','434','435','436','437','438','I60','I61','I62','I63','I64','I65','I66','I67','I68','I69') THEN 1
        WHEN d_icd.icd_code IN ('290','2900','2901','2902','2903','F00','F01','F02','F03') THEN 1
        WHEN d_icd.icd_code IN ('490','491','492','493','494','495','496','J40','J41','J42','J43','J44','J45','J46','J47') THEN 1
        WHEN d_icd.icd_code IN ('710','7100','7101','7102','7103','7104','7105','7106','7107','7108','7109','M05','M06') THEN 1
        WHEN d_icd.icd_code IN ('531','532','533','534','K25','K26','K27','K28') THEN 1
        WHEN d_icd.icd_code IN ('570','571','K70','K71','K72','K73','K74','K75','K76') THEN
          CASE WHEN d_icd.icd_code IN ('5715','K720','K721','K722','K729') THEN 2 ELSE 1 END
        WHEN d_icd.icd_code IN ('250','2500','2501','2502','2503','2504','2505','2506','2507','2508','2509','E10','E11','E12','E13','E14') THEN
          CASE WHEN d_icd.icd_code IN ('2504','2505','2506','2507','2508','2509','E104','E105','E106','E107','E108','E109','E114','E115','E116','E117','E118','E119','E134','E135','E136','E137','E138','E139','E144','E145','E146','E147','E148','E149') THEN 2 ELSE 1 END
        ELSE 0
      END
    ) AS charlson_score
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE d.subject_id IN (SELECT subject_id FROM heart_failure_cohort)
    -- Exclude heart failure codes from comorbidity burden
    AND NOT (
      REGEXP_CONTAINS(LOWER(d_icd.long_title;