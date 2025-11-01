WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 71 AND 81
),
diagnosis_flags AS (
  SELECT 
    d.hadm_id,
    MAX(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) AS has_primary,
    MAX(CASE WHEN d.seq_num > 1 THEN 1 ELSE 0 END) AS has_secondary
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_code IN ('K52.2', 'K52.3', 'K52.8', 'K62.8', 'K92.2')
  GROUP BY d.hadm_id
),
radiography_counts AS (
  SELECT 
    hc.hadm_id,
    COUNT(*) AS num_radiography_cts
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
  WHERE hc.hcpcs_cd IN (
    '70450','70460','70470','70480','70490','70500','70510','70520','70530','70540','70550','70560','70570','70580','70590',
    '71240','71250','71260','71270','71280','71290','71300','71310','71320','71330','71340','71350','71360','71370','71380','71390','71400','71410','71420','71430','71440','71450','71460','71470','71480','71490','71500','71510','71520','71530','71540','71550','71560','71570','71580','71590','71600','71610','71620','71630','71640','71650','71660','71670','71680','71690','71700','71710','71720','71730','71740','71750','71760','71770','71780','71790','71800','71810','71820','71830','71840','71850','71860','71870','71880','71890','71900','71910','71920','71930','71940','71950','71960','71970','71980','71990','72000','72010','72020','72030','72040','72050','72060','72070','72080','72090','72100','72110','72120','72130','72140','72150','72160','72170','72180','72190','72200','72210','72220','72230','72240','72250','72260','72270','72280','72290','72300','72310','72320','72330','72340','72350','72360','72370','72380','72390','72400','72410','72420','72430','72440','72450','72460','72470','72480','72490','72500','72510','72520','72530','72540','72550','72560','72570','72580','72590','72600','72610','72620','72630','72640','72650','72660','72670','72680','72690','72700','72710','72720','72730','72740','72750','72760','72770','72780','72790','72800','72810','72820','72830','72840','72850','72860','72870','72880','72890','72900','72910','72920','72930','72940','72950','72960','72970','72980','72990','73000','73010','73020','73030','73040','73050','73060','73070','73080','73090','73100','73110','73120','73130','73140','73150','73160','73170','73180','73190','73200','73210','73220','73230','73240','73250','73260','73270','73280','73290','73300','73310','73320','73330','73340','73350','73360','73370','73380','73390','73400','73410','73420','73430','73440','73450','73460','73470','73480','73490','73500','73510','73520','73530','73540','73550','73560','73570','73580','73590','73600','73610','73620','73630','73640','73650','73660','73670','73680','73690','73700','73710','73720','73730','73740','73750','73760','73770','73780','73790','73800','73810','73820','73830','73840','73850','73860','73870','73880','73890','73900','73910','73920','73930','73940','73950','73960','73970','73980','73990','74000','74010','74020','74030','74040','74050','74060','74070','74080','74090','74100','74110','74120','74130','74140','74150','74160','74170','74180','74190','74200','74210','74220'
  )
  GROUP BY hc.hadm_id
),
combined AS (
  SELECT 
    e.hadm_id,
    e.los_days,
    COALESCE(d.has_primary, 0) AS has_primary,
    COALESCE(d.has_secondary, 0) AS has_secondary,
    COALESCE(r.num_radiography_cts, 0) AS num_radiography_cts
  FROM eligible_admissions e
  LEFT JOIN diagnosis_flags d ON e.hadm_id = d.hadm_id
  LEFT JOIN radiography_counts r ON e.hadm_id = r.hadm_id
  WHERE e.los_days BETWEEN 1 AND 7 -- Only admissions with LOS 1-7 days
)
SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Other' 
  END AS los_category,
  'primary' AS diagnosis_type,
  AVG(num_radiography_cts) AS mean_radiography_cts
FROM combined
WHERE has_primary = 1
GROUP BY los_category, diagnosis_type

UNION ALL

SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Other' 
  END AS los_category,
  'secondary' AS diagnosis_type,
  AVG(num_radiography_cts) AS mean_radiography_cts
FROM combined
WHERE has_secondary = 1
GROUP BY los_category, diagnosis_type

ORDER BY los_category, diagnosis_type;